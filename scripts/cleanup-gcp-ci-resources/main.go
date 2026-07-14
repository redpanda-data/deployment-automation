package main

import (
	"context"
	"encoding/base64"
	"flag"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/fatih/color"
	"golang.org/x/sync/semaphore"
	"google.golang.org/api/compute/v1"
	"google.golang.org/api/iam/v1"
	"google.golang.org/api/option"
	"google.golang.org/api/storage/v1"
)

var (
	prefix         = flag.String("prefix", "ci-", "Deployment ID prefix to match")
	projectID      = flag.String("project-id", "", "GCP project ID (required)")
	dryRun         = flag.Bool("dry-run", false, "Preview mode - list resources without deleting")
	autoApprove    = flag.Bool("auto-approve", false, "Skip confirmation prompt")
	useBase64Creds = flag.Bool("use-gcp-creds-base64", false, "Use base64-encoded GOOGLE_CREDENTIALS_BASE64 env var")
	minAge         = flag.Duration("min-age", 0, "Only delete resources created more than this long ago (e.g. 3h). Protects concurrent builds' live resources; 0 disables the filter")

	// Colored output
	red    = color.New(color.FgRed).SprintFunc()
	green  = color.New(color.FgGreen).SprintFunc()
	yellow = color.New(color.FgYellow).SprintFunc()
	cyan   = color.New(color.FgCyan).SprintFunc()

	// Counters
	instancesDeleted   int
	groupsDeleted      int
	firewallsDeleted   int
	addressesDeleted   int
	subnetsDeleted     int
	networksDeleted    int
	serviceAcctsDeleted int
	bucketsDeleted     int
	errorsEncountered  int
)

func main() {
	flag.Parse()

	if *projectID == "" {
		fmt.Println(red("Error: --project-id is required"))
		flag.Usage()
		os.Exit(1)
	}

	ctx := context.Background()

	// Check if running in CI
	inCI := os.Getenv("CI") == "true" || os.Getenv("BUILDKITE") == "true"
	if inCI && !*autoApprove {
		fmt.Println(cyan("Running in CI environment, enabling auto-approve"))
		*autoApprove = true
	}

	// Handle credentials
	var opts []option.ClientOption
	if *useBase64Creds {
		credFile, err := setupBase64Credentials()
		if err != nil {
			fmt.Println(red(fmt.Sprintf("Failed to setup credentials: %v", err)))
			os.Exit(1)
		}
		defer os.Remove(credFile)
		opts = append(opts, option.WithCredentialsFile(credFile))
	}

	// Create clients
	computeService, err := compute.NewService(ctx, opts...)
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Failed to create compute service: %v", err)))
		os.Exit(1)
	}

	storageService, err := storage.NewService(ctx, opts...)
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Failed to create storage service: %v", err)))
		os.Exit(1)
	}

	iamService, err := iam.NewService(ctx, opts...)
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Failed to create IAM service: %v", err)))
		os.Exit(1)
	}

	// Print configuration
	fmt.Println(cyan("=== GCP CI Resource Cleanup ==="))
	fmt.Printf("Project: %s\n", *projectID)
	fmt.Printf("Scope: All regions (global cleanup)\n")
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

	// Delete resources in dependency order
	fmt.Println(cyan("=== Deleting Compute Instances ==="))
	deleteInstances(ctx, computeService)

	fmt.Println(cyan("\n=== Deleting Instance Groups ==="))
	deleteInstanceGroups(ctx, computeService)

	fmt.Println(cyan("\n=== Deleting Firewall Rules ==="))
	deleteFirewallRules(ctx, computeService)

	fmt.Println(cyan("\n=== Deleting Addresses ==="))
	deleteAddresses(ctx, computeService)

	fmt.Println(cyan("\n=== Deleting Subnetworks ==="))
	deleteSubnetworks(ctx, computeService)

	fmt.Println(cyan("\n=== Deleting VPC Networks ==="))
	deleteNetworks(ctx, computeService)

	fmt.Println(cyan("\n=== Deleting Service Accounts ==="))
	deleteServiceAccounts(ctx, iamService)

	fmt.Println(cyan("\n=== Deleting Storage Buckets ==="))
	deleteStorageBuckets(ctx, storageService)

	// Print summary
	fmt.Println(cyan("\n=== Cleanup Summary ==="))
	fmt.Printf("Compute Instances: %s\n", green(instancesDeleted))
	fmt.Printf("Instance Groups: %s\n", green(groupsDeleted))
	fmt.Printf("Firewall Rules: %s\n", green(firewallsDeleted))
	fmt.Printf("Addresses: %s\n", green(addressesDeleted))
	fmt.Printf("Subnetworks: %s\n", green(subnetsDeleted))
	fmt.Printf("VPC Networks: %s\n", green(networksDeleted))
	fmt.Printf("Service Accounts: %s\n", green(serviceAcctsDeleted))
	fmt.Printf("Storage Buckets: %s\n", green(bucketsDeleted))
	if errorsEncountered > 0 {
		fmt.Printf("Errors: %s\n", red(errorsEncountered))
		os.Exit(1)
	}
}

func setupBase64Credentials() (string, error) {
	// Check both GOOGLE_CREDENTIALS_BASE64 and GCP_CREDS (fallback)
	credsB64 := os.Getenv("GOOGLE_CREDENTIALS_BASE64")
	if credsB64 == "" {
		credsB64 = os.Getenv("GCP_CREDS")
	}
	if credsB64 == "" {
		return "", fmt.Errorf("GOOGLE_CREDENTIALS_BASE64 or GCP_CREDS environment variable not set")
	}

	creds, err := base64.StdEncoding.DecodeString(credsB64)
	if err != nil {
		return "", fmt.Errorf("failed to decode base64 credentials: %w", err)
	}

	tmpFile, err := os.CreateTemp("", "gcp-creds-*.json")
	if err != nil {
		return "", fmt.Errorf("failed to create temp file: %w", err)
	}
	defer tmpFile.Close()

	if _, err := tmpFile.Write(creds); err != nil {
		os.Remove(tmpFile.Name())
		return "", fmt.Errorf("failed to write credentials: %w", err)
	}

	return tmpFile.Name(), nil
}

// oldEnough reports whether a resource with the given RFC3339 creation
// timestamp clears the -min-age bar. When min-age is set, resources with a
// missing/unparseable timestamp are treated as NOT old enough: with
// concurrent CI builds, deleting a resource of unknown age risks killing a
// live lane.
func oldEnough(creationTimestamp string) bool {
	if *minAge == 0 {
		return true
	}
	t, err := time.Parse(time.RFC3339, creationTimestamp)
	if err != nil {
		return false
	}
	return time.Since(t) >= *minAge
}

func deleteInstances(ctx context.Context, service *compute.Service) {
	// Get all instances across all zones
	aggList, err := service.Instances.AggregatedList(*projectID).Do()
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error listing instances: %v", err)))
		errorsEncountered++
		return
	}

	found := false
	for zone, instanceList := range aggList.Items {
		if instanceList.Instances == nil {
			continue
		}

		for _, instance := range instanceList.Instances {
			if !strings.HasPrefix(instance.Name, *prefix) || strings.Contains(instance.Name, "devex") {
				continue
			}
			if !oldEnough(instance.CreationTimestamp) {
				fmt.Printf("%s\n", yellow("Skipping (younger than min-age): "+instance.Name))
				continue
			}

			found = true

			if *dryRun {
				fmt.Printf("%s (zone: %s)\n",
					cyan("Would delete: "+instance.Name), extractZone(zone))
			} else {
				fmt.Printf("%s (zone: %s)\n", green("Deleting: "+instance.Name), extractZone(zone))
				op, err := service.Instances.Delete(*projectID, extractZone(zone), instance.Name).Do()
				if err != nil && !isNotFoundError(err) {
					fmt.Println(red(fmt.Sprintf("Error deleting instance: %v", err)))
					errorsEncountered++
					continue
				}
				if err := waitForZoneOperation(service, *projectID, extractZone(zone), op.Name); err != nil {
					fmt.Println(yellow(fmt.Sprintf("Warning waiting for operation: %v", err)))
				}
				instancesDeleted++
			}
		}
	}

	if !found {
		fmt.Println("No instances found")
	}
}

func deleteInstanceGroups(ctx context.Context, service *compute.Service) {
	// Get all instance groups across all zones
	aggList, err := service.InstanceGroups.AggregatedList(*projectID).Do()
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error listing instance groups: %v", err)))
		errorsEncountered++
		return
	}

	found := false
	for zone, groupList := range aggList.Items {
		if groupList.InstanceGroups == nil {
			continue
		}

		for _, group := range groupList.InstanceGroups {
			if !strings.HasPrefix(group.Name, *prefix) || strings.Contains(group.Name, "devex") {
				continue
			}
			if !oldEnough(group.CreationTimestamp) {
				fmt.Printf("%s\n", yellow("Skipping (younger than min-age): "+group.Name))
				continue
			}

			found = true
			if *dryRun {
				fmt.Printf("%s (zone: %s)\n", cyan("Would delete: "+group.Name), extractZone(zone))
			} else {
				fmt.Printf("%s (zone: %s)\n", green("Deleting: "+group.Name), extractZone(zone))
				op, err := service.InstanceGroups.Delete(*projectID, extractZone(zone), group.Name).Do()
				if err != nil && !isNotFoundError(err) {
					fmt.Println(red(fmt.Sprintf("Error deleting instance group: %v", err)))
					errorsEncountered++
					continue
				}
				if err := waitForZoneOperation(service, *projectID, extractZone(zone), op.Name); err != nil {
					fmt.Println(yellow(fmt.Sprintf("Warning waiting for operation: %v", err)))
				}
				groupsDeleted++
			}
		}
	}

	if !found {
		fmt.Println("No instance groups found")
	}
}

func deleteFirewallRules(ctx context.Context, service *compute.Service) {
	firewalls, err := service.Firewalls.List(*projectID).Do()
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error listing firewalls: %v", err)))
		errorsEncountered++
		return
	}

	if len(firewalls.Items) == 0 {
		fmt.Println("No firewall rules found")
		return
	}

	found := false
	for _, firewall := range firewalls.Items {
		if !strings.HasPrefix(firewall.Name, *prefix) || strings.Contains(firewall.Name, "devex") {
			continue
		}
		if !oldEnough(firewall.CreationTimestamp) {
			fmt.Printf("%s\n", yellow("Skipping (younger than min-age): "+firewall.Name))
			continue
		}

		found = true
		if *dryRun {
			fmt.Printf("%s\n", cyan("Would delete: "+firewall.Name))
		} else {
			fmt.Printf("%s\n", green("Deleting: "+firewall.Name))
			op, err := service.Firewalls.Delete(*projectID, firewall.Name).Do()
			if err != nil && !isNotFoundError(err) {
				fmt.Println(red(fmt.Sprintf("Error deleting firewall: %v", err)))
				errorsEncountered++
				continue
			}
			if err := waitForGlobalOperation(service, *projectID, op.Name); err != nil {
				fmt.Println(yellow(fmt.Sprintf("Warning waiting for operation: %v", err)))
			}
			firewallsDeleted++
		}
	}

	if !found {
		fmt.Println("No firewall rules found")
	}
}

func deleteAddresses(ctx context.Context, service *compute.Service) {
	addresses, err := service.Addresses.AggregatedList(*projectID).Do()
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error listing addresses: %v", err)))
		errorsEncountered++
		return
	}

	found := false
	for regionURL, addressList := range addresses.Items {
		if addressList.Addresses == nil {
			continue
		}

		for _, address := range addressList.Addresses {
			if !strings.HasPrefix(address.Name, *prefix) || strings.Contains(address.Name, "devex") {
				continue
			}
			if !oldEnough(address.CreationTimestamp) {
				fmt.Printf("%s\n", yellow("Skipping (younger than min-age): "+address.Name))
				continue
			}

			found = true
			if *dryRun {
				fmt.Printf("%s (region: %s)\n", cyan("Would delete: "+address.Name), extractRegion(regionURL))
			} else {
				fmt.Printf("%s (region: %s)\n", green("Deleting: "+address.Name), extractRegion(regionURL))
				op, err := service.Addresses.Delete(*projectID, extractRegion(regionURL), address.Name).Do()
				if err != nil && !isNotFoundError(err) {
					fmt.Println(red(fmt.Sprintf("Error deleting address: %v", err)))
					errorsEncountered++
					continue
				}
				if err := waitForRegionOperation(service, *projectID, extractRegion(regionURL), op.Name); err != nil {
					fmt.Println(yellow(fmt.Sprintf("Warning waiting for operation: %v", err)))
				}
				addressesDeleted++
			}
		}
	}

	if !found {
		fmt.Println("No addresses found")
	}
}

func deleteSubnetworks(ctx context.Context, service *compute.Service) {
	subnets, err := service.Subnetworks.AggregatedList(*projectID).Do()
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error listing subnetworks: %v", err)))
		errorsEncountered++
		return
	}

	found := false
	for regionURL, subnetList := range subnets.Items {
		if subnetList.Subnetworks == nil {
			continue
		}

		for _, subnet := range subnetList.Subnetworks {
			if !strings.HasPrefix(subnet.Name, *prefix) || strings.Contains(subnet.Name, "devex") {
				continue
			}
			if !oldEnough(subnet.CreationTimestamp) {
				fmt.Printf("%s\n", yellow("Skipping (younger than min-age): "+subnet.Name))
				continue
			}

			found = true
			if *dryRun {
				fmt.Printf("%s (region: %s)\n", cyan("Would delete: "+subnet.Name), extractRegion(regionURL))
			} else {
				fmt.Printf("%s (region: %s)\n", green("Deleting: "+subnet.Name), extractRegion(regionURL))
				op, err := service.Subnetworks.Delete(*projectID, extractRegion(regionURL), subnet.Name).Do()
				if err != nil && !isNotFoundError(err) {
					fmt.Println(red(fmt.Sprintf("Error deleting subnetwork: %v", err)))
					errorsEncountered++
					continue
				}
				if err := waitForRegionOperation(service, *projectID, extractRegion(regionURL), op.Name); err != nil {
					fmt.Println(yellow(fmt.Sprintf("Warning waiting for operation: %v", err)))
				}
				subnetsDeleted++
			}
		}
	}

	if !found {
		fmt.Println("No subnetworks found")
	}
}

func deleteNetworks(ctx context.Context, service *compute.Service) {
	networks, err := service.Networks.List(*projectID).Do()
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error listing networks: %v", err)))
		errorsEncountered++
		return
	}

	found := false
	for _, network := range networks.Items {
		if !strings.HasPrefix(network.Name, *prefix) || strings.Contains(network.Name, "devex") {
			continue
		}
		if !oldEnough(network.CreationTimestamp) {
			fmt.Printf("%s\n", yellow("Skipping (younger than min-age): "+network.Name))
			continue
		}

		found = true
		if *dryRun {
			fmt.Printf("%s\n", cyan("Would delete: "+network.Name))
		} else {
			fmt.Printf("%s\n", green("Deleting: "+network.Name))
			op, err := service.Networks.Delete(*projectID, network.Name).Do()
			if err != nil && !isNotFoundError(err) {
				fmt.Println(red(fmt.Sprintf("Error deleting network: %v", err)))
				errorsEncountered++
				continue
			}
			if err := waitForGlobalOperation(service, *projectID, op.Name); err != nil {
				fmt.Println(yellow(fmt.Sprintf("Warning waiting for operation: %v", err)))
			}
			networksDeleted++
		}
	}

	if !found {
		fmt.Println("No networks found")
	}
}

func deleteServiceAccounts(ctx context.Context, service *iam.Service) {
	accounts, err := service.Projects.ServiceAccounts.List(fmt.Sprintf("projects/%s", *projectID)).Do()
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error listing service accounts: %v", err)))
		errorsEncountered++
		return
	}

	found := false
	for _, account := range accounts.Accounts {
		// Extract short name from email (e.g., ci-xyz-rp-admin@project.iam.gserviceaccount.com)
		parts := strings.Split(account.Email, "@")
		if len(parts) == 0 {
			continue
		}
		shortName := parts[0]

		if !strings.HasPrefix(shortName, *prefix) || strings.Contains(shortName, "devex") {
			continue
		}
		// Service accounts expose no creation timestamp; under min-age skip
		// them rather than risk deleting one a live lane authenticates with.
		// The manual cleanup (no min-age) still reaps them.
		if *minAge != 0 {
			fmt.Printf("%s\n", yellow("Skipping (min-age set, creation time unknown): "+account.Email))
			continue
		}

		found = true
		if *dryRun {
			fmt.Printf("%s\n", cyan("Would delete: "+account.Email))
		} else {
			fmt.Printf("%s\n", green("Deleting: "+account.Email))
			_, err := service.Projects.ServiceAccounts.Delete(account.Name).Do()
			if err != nil && !isNotFoundError(err) {
				fmt.Println(red(fmt.Sprintf("Error deleting service account: %v", err)))
				errorsEncountered++
				continue
			}
			serviceAcctsDeleted++
		}
	}

	if !found {
		fmt.Println("No service accounts found")
	}
}

func deleteStorageBuckets(ctx context.Context, service *storage.Service) {
	buckets, err := service.Buckets.List(*projectID).Do()
	if err != nil {
		fmt.Println(red(fmt.Sprintf("Error listing buckets: %v", err)))
		errorsEncountered++
		return
	}

	found := false
	for _, bucket := range buckets.Items {
		if !strings.HasPrefix(bucket.Name, *prefix) || strings.Contains(bucket.Name, "devex") {
			continue
		}
		if !oldEnough(bucket.TimeCreated) {
			fmt.Printf("%s\n", yellow("Skipping (younger than min-age): "+bucket.Name))
			continue
		}

		found = true

		if *dryRun {
			fmt.Printf("%s\n", cyan("Would delete: "+bucket.Name))
		} else {
			fmt.Printf("%s\n", green("Deleting: "+bucket.Name))
			if err := emptyAndDeleteBucket(ctx, service, bucket.Name); err != nil {
				fmt.Println(red(fmt.Sprintf("Error deleting bucket: %v", err)))
				errorsEncountered++
				continue
			}
			bucketsDeleted++
		}
	}

	if !found {
		fmt.Println("No buckets found")
	}
}

func emptyAndDeleteBucket(ctx context.Context, service *storage.Service, bucketName string) error {
	// List and delete all objects (with parallel execution)
	objects, err := service.Objects.List(bucketName).Do()
	if err != nil {
		return err
	}

	// Use semaphore to limit concurrent deletions
	sem := semaphore.NewWeighted(50)
	var wg sync.WaitGroup
	var mu sync.Mutex
	var firstErr error

	for _, object := range objects.Items {
		wg.Add(1)
		go func(objName string) {
			defer wg.Done()
			if err := sem.Acquire(ctx, 1); err != nil {
				return
			}
			defer sem.Release(1)

			if err := service.Objects.Delete(bucketName, objName).Do(); err != nil {
				mu.Lock()
				if firstErr == nil {
					firstErr = err
				}
				mu.Unlock()
			}
		}(object.Name)
	}

	wg.Wait()

	if firstErr != nil {
		return firstErr
	}

	// Delete bucket
	return service.Buckets.Delete(bucketName).Do()
}

func waitForZoneOperation(service *compute.Service, project, zone, opName string) error {
	for i := 0; i < 60; i++ {
		op, err := service.ZoneOperations.Get(project, zone, opName).Do()
		if err != nil {
			return err
		}
		if op.Status == "DONE" {
			if op.Error != nil {
				return fmt.Errorf("operation error: %v", op.Error)
			}
			return nil
		}
		time.Sleep(2 * time.Second)
	}
	return fmt.Errorf("timeout waiting for operation")
}

func waitForRegionOperation(service *compute.Service, project, region, opName string) error {
	for i := 0; i < 60; i++ {
		op, err := service.RegionOperations.Get(project, region, opName).Do()
		if err != nil {
			return err
		}
		if op.Status == "DONE" {
			if op.Error != nil {
				return fmt.Errorf("operation error: %v", op.Error)
			}
			return nil
		}
		time.Sleep(2 * time.Second)
	}
	return fmt.Errorf("timeout waiting for operation")
}

func waitForGlobalOperation(service *compute.Service, project, opName string) error {
	for i := 0; i < 60; i++ {
		op, err := service.GlobalOperations.Get(project, opName).Do()
		if err != nil {
			return err
		}
		if op.Status == "DONE" {
			if op.Error != nil {
				return fmt.Errorf("operation error: %v", op.Error)
			}
			return nil
		}
		time.Sleep(2 * time.Second)
	}
	return fmt.Errorf("timeout waiting for operation")
}

func extractZone(zoneURL string) string {
	parts := strings.Split(zoneURL, "/")
	if len(parts) > 0 {
		return parts[len(parts)-1]
	}
	return zoneURL
}

func extractRegion(regionURL string) string {
	parts := strings.Split(regionURL, "/")
	if len(parts) > 0 {
		return parts[len(parts)-1]
	}
	return regionURL
}

func isNotFoundError(err error) bool {
	if err == nil {
		return false
	}
	errStr := err.Error()
	return strings.Contains(errStr, "notFound") ||
		strings.Contains(errStr, "404") ||
		strings.Contains(errStr, "Not Found")
}