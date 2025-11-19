package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/fatih/color"
)

var (
	prefix           = flag.String("prefix", "ci-", "Deployment ID prefix to match")
	region           = flag.String("region", "us-east-2,us-west-2", "AWS regions (comma-separated)")
	dryRun           = flag.Bool("dry-run", false, "Preview mode - list resources without deleting")
	autoApprove      = flag.Bool("auto-approve", false, "Skip confirmation prompt")
	verifyDefaultVPC = flag.Bool("verify-default-vpc", true, "Verify using default VPC before proceeding")

	// Colored output
	red    = color.New(color.FgRed).SprintFunc()
	green  = color.New(color.FgGreen).SprintFunc()
	yellow = color.New(color.FgYellow).SprintFunc()
	cyan   = color.New(color.FgCyan).SprintFunc()

	// Counters
	instancesDeleted int
	volumesDeleted   int
	secGroupsDeleted int
	iamDeleted       int
	keyPairsDeleted  int
	bucketsDeleted   int
	errorsEncountered int
)

func main() {
	flag.Parse()

	ctx := context.Background()

	// Check if running in CI
	inCI := os.Getenv("CI") == "true" || os.Getenv("BUILDKITE") == "true"
	if inCI && !*autoApprove {
		fmt.Println(cyan("Running in CI environment, enabling auto-approve"))
		*autoApprove = true
	}

	// Parse regions
	regions := strings.Split(*region, ",")
	for i, r := range regions {
		regions[i] = strings.TrimSpace(r)
	}

	// Print configuration
	fmt.Println(cyan("=== AWS CI Resource Cleanup ==="))
	fmt.Printf("Regions: %s\n", strings.Join(regions, ", "))
	fmt.Printf("Prefix: %s\n", *prefix)
	fmt.Printf("Dry-run: %v\n", *dryRun)
	fmt.Println()

	// Confirm before proceeding
	if !*dryRun && !*autoApprove {
		fmt.Print(yellow("This will delete resources. Continue? (yes/no): "))
		var response string
		fmt.Scanln(&response)
		if response != "yes" {
			fmt.Println("Aborted.")
			os.Exit(0)
		}
	}

	// Process each region
	for _, currentRegion := range regions {
		fmt.Println(cyan(fmt.Sprintf("\n========== Processing Region: %s ==========", currentRegion)))

		// Load AWS config for this region
		cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(currentRegion))
		if err != nil {
			fmt.Println(red(fmt.Sprintf("Failed to load AWS config for region %s: %v", currentRegion, err)))
			errorsEncountered++
			continue
		}

		ec2Client := ec2.NewFromConfig(cfg)
		iamClient := iam.NewFromConfig(cfg)
		s3Client := s3.NewFromConfig(cfg)

		// Verify default VPC usage (only once for first region)
		if *verifyDefaultVPC && currentRegion == regions[0] {
			if err := checkDefaultVPC(ctx, ec2Client); err != nil {
				fmt.Println(red(fmt.Sprintf("VPC verification failed: %v", err)))
				os.Exit(1)
			}
		}

		// Delete resources in dependency order
		fmt.Println(cyan("=== Deleting EC2 Instances ==="))
		deleteInstances(ctx, ec2Client)

		fmt.Println(cyan("\n=== Deleting EBS Volumes ==="))
		deleteVolumes(ctx, ec2Client)

		fmt.Println(cyan("\n=== Deleting Security Groups ==="))
		deleteSecurityGroups(ctx, ec2Client)

		fmt.Println(cyan("\n=== Deleting Placement Groups ==="))
		deletePlacementGroups(ctx, ec2Client)

		fmt.Println(cyan("\n=== Deleting Key Pairs ==="))
		deleteKeyPairs(ctx, ec2Client)

		// IAM and S3 are global - only process once
		if currentRegion == regions[0] {
			fmt.Println(cyan("\n=== Deleting IAM Resources ==="))
			deleteIAMResources(ctx, iamClient)

			fmt.Println(cyan("\n=== Deleting S3 Buckets ==="))
			deleteS3Buckets(ctx, s3Client)
		}
	}

	// Print summary
	fmt.Println(cyan("\n=== Cleanup Summary ==="))
	fmt.Printf("EC2 Instances: %s\n", green(instancesDeleted))
	fmt.Printf("EBS Volumes: %s\n", green(volumesDeleted))
	fmt.Printf("Security Groups: %s\n", green(secGroupsDeleted))
	fmt.Printf("IAM Resources: %s\n", green(iamDeleted))
	fmt.Printf("Key Pairs: %s\n", green(keyPairsDeleted))
	fmt.Printf("S3 Buckets: %s\n", green(bucketsDeleted))
	if errorsEncountered > 0 {
		fmt.Printf("Errors: %s\n", red(errorsEncountered))
		os.Exit(1)
	}
}

func checkDefaultVPC(ctx context.Context, client *ec2.Client) error {
	vpcs, err := client.DescribeVpcs(ctx, &ec2.DescribeVpcsInput{
		Filters: []types.Filter{{Name: aws.String("isDefault"), Values: []string{"true"}}},
	})
	if err != nil {
		return err
	}

	if len(vpcs.Vpcs) == 0 {
		return fmt.Errorf("no default VPC found - this script requires default VPC usage")
	}

	fmt.Println(yellow("⚠️  Using default VPC - VPC components will be preserved"))
	fmt.Printf("Default VPC ID: %s\n\n", *vpcs.Vpcs[0].VpcId)
	return nil
}

func deleteInstances(ctx context.Context, client *ec2.Client) {
	result, err := client.DescribeInstances(ctx, &ec2.DescribeInstancesInput{
		Filters: []types.Filter{
			{Name: aws.String("tag:Name"), Values: []string{*prefix + "*"}},
			{Name: aws.String("instance-state-name"), Values: []string{"running", "stopped", "stopping", "pending"}},
		},
	})
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error describing instances: %v", err)))
		errorsEncountered++
		return
	}

	var instanceIDs []string
	for _, reservation := range result.Reservations {
		for _, instance := range reservation.Instances {
			instanceIDs = append(instanceIDs, *instance.InstanceId)
			if *dryRun {
				fmt.Printf("%s\n", cyan("Would delete: "+*instance.InstanceId))
			} else {
				fmt.Printf("%s\n", green("Terminating: "+*instance.InstanceId))
			}
		}
	}

	if len(instanceIDs) == 0 {
		fmt.Println("No instances found")
		return
	}

	if !*dryRun {
		_, err := client.TerminateInstances(ctx, &ec2.TerminateInstancesInput{
			InstanceIds: instanceIDs,
		})
		if err != nil {
			fmt.Println(red(fmt.Sprintf("Error terminating instances: %v", err)))
			errorsEncountered++
			return
		}

		// Wait for instances to terminate
		fmt.Println(yellow("Waiting for instances to terminate..."))
		waiter := ec2.NewInstanceTerminatedWaiter(client)
		if err := waiter.Wait(ctx, &ec2.DescribeInstancesInput{
			InstanceIds: instanceIDs,
		}, 5*time.Minute); err != nil {
			fmt.Println(yellow(fmt.Sprintf("Warning: wait timeout: %v", err)))
		}
		instancesDeleted = len(instanceIDs)
	}
}

func deleteVolumes(ctx context.Context, client *ec2.Client) {
	result, err := client.DescribeVolumes(ctx, &ec2.DescribeVolumesInput{
		Filters: []types.Filter{
			{Name: aws.String("tag:Name"), Values: []string{*prefix + "*"}},
			{Name: aws.String("status"), Values: []string{"available"}},
		},
	})
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error describing volumes: %v", err)))
		errorsEncountered++
		return
	}

	if len(result.Volumes) == 0 {
		fmt.Println("No volumes found")
		return
	}

	for _, volume := range result.Volumes {
		if *dryRun {
			fmt.Printf("%s\n", cyan("Would delete: "+*volume.VolumeId))
		} else {
			fmt.Printf("%s\n", green("Deleting: "+*volume.VolumeId))
			_, err := client.DeleteVolume(ctx, &ec2.DeleteVolumeInput{
				VolumeId: volume.VolumeId,
			})
			if err != nil && !isNotFoundError(err) {
				fmt.Println(red(fmt.Sprintf("Error deleting volume %s: %v", *volume.VolumeId, err)))
				errorsEncountered++
			} else {
				volumesDeleted++
			}
		}
	}
}

func deleteSecurityGroups(ctx context.Context, client *ec2.Client) {
	result, err := client.DescribeSecurityGroups(ctx, &ec2.DescribeSecurityGroupsInput{
		Filters: []types.Filter{
			{Name: aws.String("group-name"), Values: []string{*prefix + "*"}},
		},
	})
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error describing security groups: %v", err)))
		errorsEncountered++
		return
	}

	if len(result.SecurityGroups) == 0 {
		fmt.Println("No security groups found")
		return
	}

	for _, sg := range result.SecurityGroups {
		// Never delete default security group
		if *sg.GroupName == "default" {
			continue
		}

		if *dryRun {
			fmt.Printf("%s (%s)\n", cyan("Would delete: "+*sg.GroupName), *sg.GroupId)
		} else {
			// Revoke all ingress rules
			if len(sg.IpPermissions) > 0 {
				_, err := client.RevokeSecurityGroupIngress(ctx, &ec2.RevokeSecurityGroupIngressInput{
					GroupId:       sg.GroupId,
					IpPermissions: sg.IpPermissions,
				})
				if err != nil && !isNotFoundError(err) {
					fmt.Println(yellow(fmt.Sprintf("Warning revoking ingress: %v", err)))
				}
			}

			// Revoke all egress rules
			if len(sg.IpPermissionsEgress) > 0 {
				_, err := client.RevokeSecurityGroupEgress(ctx, &ec2.RevokeSecurityGroupEgressInput{
					GroupId:       sg.GroupId,
					IpPermissions: sg.IpPermissionsEgress,
				})
				if err != nil && !isNotFoundError(err) {
					fmt.Println(yellow(fmt.Sprintf("Warning revoking egress: %v", err)))
				}
			}

			// Delete security group
			fmt.Printf("%s (%s)\n", green("Deleting: "+*sg.GroupName), *sg.GroupId)
			_, err := client.DeleteSecurityGroup(ctx, &ec2.DeleteSecurityGroupInput{
				GroupId: sg.GroupId,
			})
			if err != nil && !isNotFoundError(err) {
				fmt.Println(red(fmt.Sprintf("Error deleting security group %s: %v", *sg.GroupName, err)))
				errorsEncountered++
			} else {
				secGroupsDeleted++
			}
		}
	}
}

func deletePlacementGroups(ctx context.Context, client *ec2.Client) {
	result, err := client.DescribePlacementGroups(ctx, &ec2.DescribePlacementGroupsInput{
		Filters: []types.Filter{
			{Name: aws.String("group-name"), Values: []string{*prefix + "*"}},
		},
	})
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error describing placement groups: %v", err)))
		errorsEncountered++
		return
	}

	if len(result.PlacementGroups) == 0 {
		fmt.Println("No placement groups found")
		return
	}

	for _, pg := range result.PlacementGroups {
		if *dryRun {
			fmt.Printf("%s\n", cyan("Would delete: "+*pg.GroupName))
		} else {
			fmt.Printf("%s\n", green("Deleting: "+*pg.GroupName))
			_, err := client.DeletePlacementGroup(ctx, &ec2.DeletePlacementGroupInput{
				GroupName: pg.GroupName,
			})
			if err != nil && !isNotFoundError(err) {
				fmt.Println(red(fmt.Sprintf("Error deleting placement group %s: %v", *pg.GroupName, err)))
				errorsEncountered++
			}
		}
	}
}

func deleteIAMResources(ctx context.Context, client *iam.Client) {
	// Delete instance profiles
	profilesResult, err := client.ListInstanceProfiles(ctx, &iam.ListInstanceProfilesInput{})
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error listing instance profiles: %v", err)))
		errorsEncountered++
		return
	}

	for _, profile := range profilesResult.InstanceProfiles {
		if !strings.HasPrefix(*profile.InstanceProfileName, *prefix) {
			continue
		}

		if *dryRun {
			fmt.Printf("%s\n", cyan("Would delete instance profile: "+*profile.InstanceProfileName))
		} else {
			// Remove role from instance profile
			for _, role := range profile.Roles {
				_, _ = client.RemoveRoleFromInstanceProfile(ctx, &iam.RemoveRoleFromInstanceProfileInput{
					InstanceProfileName: profile.InstanceProfileName,
					RoleName:            role.RoleName,
				})
			}

			fmt.Printf("%s\n", green("Deleting instance profile: "+*profile.InstanceProfileName))
			_, err := client.DeleteInstanceProfile(ctx, &iam.DeleteInstanceProfileInput{
				InstanceProfileName: profile.InstanceProfileName,
			})
			if err != nil && !isNotFoundError(err) {
				fmt.Println(red(fmt.Sprintf("Error deleting instance profile: %v", err)))
				errorsEncountered++
			} else {
				iamDeleted++
			}
		}
	}

	// Delete roles
	rolesResult, err := client.ListRoles(ctx, &iam.ListRolesInput{})
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error listing roles: %v", err)))
		errorsEncountered++
		return
	}

	for _, role := range rolesResult.Roles {
		if !strings.HasPrefix(*role.RoleName, *prefix) {
			continue
		}

		if *dryRun {
			fmt.Printf("%s\n", cyan("Would delete role: "+*role.RoleName))
		} else {
			// Detach all attached policies
			policiesResult, err := client.ListAttachedRolePolicies(ctx, &iam.ListAttachedRolePoliciesInput{
				RoleName: role.RoleName,
			})
			if err == nil {
				for _, policy := range policiesResult.AttachedPolicies {
					_, _ = client.DetachRolePolicy(ctx, &iam.DetachRolePolicyInput{
						RoleName:  role.RoleName,
						PolicyArn: policy.PolicyArn,
					})
				}
			}

			// Delete inline policies
			inlinePoliciesResult, err := client.ListRolePolicies(ctx, &iam.ListRolePoliciesInput{
				RoleName: role.RoleName,
			})
			if err == nil {
				for _, policyName := range inlinePoliciesResult.PolicyNames {
					_, _ = client.DeleteRolePolicy(ctx, &iam.DeleteRolePolicyInput{
						RoleName:   role.RoleName,
						PolicyName: aws.String(policyName),
					})
				}
			}

			fmt.Printf("%s\n", green("Deleting role: "+*role.RoleName))
			_, err = client.DeleteRole(ctx, &iam.DeleteRoleInput{
				RoleName: role.RoleName,
			})
			if err != nil && !isNotFoundError(err) {
				fmt.Println(red(fmt.Sprintf("Error deleting role: %v", err)))
				errorsEncountered++
			} else {
				iamDeleted++
			}
		}
	}
}

func deleteKeyPairs(ctx context.Context, client *ec2.Client) {
	result, err := client.DescribeKeyPairs(ctx, &ec2.DescribeKeyPairsInput{
		Filters: []types.Filter{
			{Name: aws.String("key-name"), Values: []string{*prefix + "*"}},
		},
	})
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error describing key pairs: %v", err)))
		errorsEncountered++
		return
	}

	if len(result.KeyPairs) == 0 {
		fmt.Println("No key pairs found")
		return
	}

	for _, kp := range result.KeyPairs {
		if *dryRun {
			fmt.Printf("%s\n", cyan("Would delete: "+*kp.KeyName))
		} else {
			fmt.Printf("%s\n", green("Deleting: "+*kp.KeyName))
			_, err := client.DeleteKeyPair(ctx, &ec2.DeleteKeyPairInput{
				KeyName: kp.KeyName,
			})
			if err != nil && !isNotFoundError(err) {
				fmt.Println(red(fmt.Sprintf("Error deleting key pair %s: %v", *kp.KeyName, err)))
				errorsEncountered++
			} else {
				keyPairsDeleted++
			}
		}
	}
}

func deleteS3Buckets(ctx context.Context, s3Client *s3.Client) {
	result, err := s3Client.ListBuckets(ctx, &s3.ListBucketsInput{})
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error listing buckets: %v", err)))
		errorsEncountered++
		return
	}

	found := false
	for _, bucket := range result.Buckets {
		if !strings.HasPrefix(*bucket.Name, *prefix) {
			continue
		}

		found = true

		if *dryRun {
			fmt.Printf("%s\n", cyan("Would delete: "+*bucket.Name))
		} else {
			fmt.Printf("%s\n", green("Deleting: "+*bucket.Name))
			if err := emptyAndDeleteBucket(ctx, *bucket.Name); err != nil {
				fmt.Println(red(fmt.Sprintf("Error deleting bucket %s: %v", *bucket.Name, err)))
				errorsEncountered++
			} else {
				bucketsDeleted++
			}
		}
	}

	if !found {
		fmt.Println("No buckets found")
	}
}

func emptyAndDeleteBucket(ctx context.Context, bucketName string) error {
	// Get bucket region
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	// Use us-east-1 to get bucket location (works globally)
	s3Global := s3.NewFromConfig(cfg, func(o *s3.Options) {
		o.Region = "us-east-1"
	})

	location, err := s3Global.GetBucketLocation(ctx, &s3.GetBucketLocationInput{
		Bucket: aws.String(bucketName),
	})
	if err != nil {
		return fmt.Errorf("failed to get bucket location: %w", err)
	}

	// Determine bucket region (empty LocationConstraint means us-east-1)
	bucketRegion := "us-east-1"
	if location.LocationConstraint != "" {
		bucketRegion = string(location.LocationConstraint)
	}

	// Create region-specific S3 client
	regionalClient := s3.NewFromConfig(cfg, func(o *s3.Options) {
		o.Region = bucketRegion
	})

	fmt.Printf("  (region: %s) ", bucketRegion)

	// Delete all object versions
	versionsResult, err := regionalClient.ListObjectVersions(ctx, &s3.ListObjectVersionsInput{
		Bucket: aws.String(bucketName),
	})
	if err != nil {
		return err
	}

	// Delete versions
	for _, version := range versionsResult.Versions {
		_, err := regionalClient.DeleteObject(ctx, &s3.DeleteObjectInput{
			Bucket:    aws.String(bucketName),
			Key:       version.Key,
			VersionId: version.VersionId,
		})
		if err != nil {
			fmt.Println(yellow(fmt.Sprintf("Warning deleting version %s: %v", *version.Key, err)))
		}
	}

	// Delete delete markers
	for _, marker := range versionsResult.DeleteMarkers {
		_, err := regionalClient.DeleteObject(ctx, &s3.DeleteObjectInput{
			Bucket:    aws.String(bucketName),
			Key:       marker.Key,
			VersionId: marker.VersionId,
		})
		if err != nil {
			fmt.Println(yellow(fmt.Sprintf("Warning deleting marker %s: %v", *marker.Key, err)))
		}
	}

	// Delete bucket
	_, err = regionalClient.DeleteBucket(ctx, &s3.DeleteBucketInput{
		Bucket: aws.String(bucketName),
	})
	return err
}

func isNotFoundError(err error) bool {
	if err == nil {
		return false
	}
	errStr := err.Error()
	return strings.Contains(errStr, "NotFound") ||
		strings.Contains(errStr, "NoSuchEntity") ||
		strings.Contains(errStr, "NoSuchBucket") ||
		strings.Contains(errStr, "InvalidGroup.NotFound") ||
		strings.Contains(errStr, "InvalidKeyPair.NotFound") ||
		strings.Contains(errStr, "InvalidInstanceID.NotFound") ||
		strings.Contains(errStr, "InvalidVolume.NotFound") ||
		strings.Contains(errStr, "InvalidPlacementGroup.Unknown")
}