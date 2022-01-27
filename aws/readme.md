# AWS Deployment

This Terraform module will deploy VMs on AWS EC2, with a security group which allows inbound traffic on ports used by Redpanda and monitoring tools.

After completing these steps, please follow the required steps in the [project readme](../README.md) to deploy Redpanda to the new VMs.

1. Create AWS secret keys and provide them to terraform https://registry.terraform.io/providers/hashicorp/aws/latest/docs#environment-variables
2. `cd` to the `aws` directory and run `terraform init`.
3. `terraform apply` to create the resources on AWS.

Example: `terraform apply -var="instance_type=i3.large" -var="nodes=3"`


## Requirements

| Name | Version |
|------|---------|
| aws | 3.73.0 |
| local | 2.1.0 |
| random | 3.1.0 |

## Providers

| Name | Version |
|------|---------|
| aws | 3.73.0 |
| local | 2.1.0 |
| random | 3.1.0 |

## Modules

No Modules.

## Resources

| Name |
|------|
| [aws_instance](https://registry.terraform.io/providers/hashicorp/aws/3.73.0/docs/resources/instance) |
| [aws_key_pair](https://registry.terraform.io/providers/hashicorp/aws/3.73.0/docs/resources/key_pair) |
| [aws_security_group](https://registry.terraform.io/providers/hashicorp/aws/3.73.0/docs/resources/security_group) |
| [local_file](https://registry.terraform.io/providers/hashicorp/local/2.1.0/docs/resources/file) |
| [random_uuid](https://registry.terraform.io/providers/hashicorp/random/3.1.0/docs/resources/uuid) |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| aws\_region | The AWS region to deploy the infrastructure on | `string` | `"us-west-2"` | no |
| distro | The default distribution to base the cluster on | `string` | `"ubuntu-focal"` | no |
| distro\_ami | n/a | `map(string)` | <pre>{<br>  "amazon-linux-2": "ami-01ce4793a2f45922e",<br>  "debian-buster": "ami-0f7939d313699273c",<br>  "debian-stretch": "ami-072ad3956e05c814c",<br>  "fedora-31": "ami-0e82cc6ce8f393d4b",<br>  "fedora-32": "ami-020405ee5d5747724",<br>  "rhel-8": "ami-087c2c50437d0b80d",<br>  "ubuntu-bionic": "ami-0c1ab2d66f996cd4b",<br>  "ubuntu-focal": "ami-02c45ea799467b51b",<br> "ubuntu-hirsute": "ami-035649ffeb04ce758" <br>}</pre> | no |
| distro\_ssh\_user | The default user used by the AWS AMIs | `map(string)` | <pre>{<br>  "amazon-linux-2": "ec2-user",<br>  "debian-buster": "admin",<br>  "debian-stretch": "admin",<br>  "fedora-31": "fedora",<br>  "fedora-32": "fedora",<br>  "rhel-8": "ec2-user",<br>  "ubuntu-\*": "ubuntu" <br>}</pre> | no |
| enable\_monitoring | Setup a prometheus/grafana instance | `bool` | `true` | no |
| instance\_type | Default redpanda instance type to create | `string` | `"i3.2xlarge"` | no |
| nodes | The number of nodes to deploy | `number` | `"3"` | no |
| prometheus\_instance\_type | Instant type of the prometheus/grafana node | `string` | `"c5.2xlarge"` | no |
| public\_key\_path | The public key used to ssh to the hosts | `string` | `"~/.ssh/id_rsa.pub"` | no |

### Client Inputs
By default, no client VMs are provisioned. If you want to also provision client
hosts, you can set the following options:

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| clients | Number of client VMs, if any, to deploy. | `number` | `0` | no |
| client\_distro | Linux distribution to use for clients, if any. | `string` | `ubuntu-focal` | no |
| client\_instance\_type | EC2 instance type for client hosts. | `string` | `m5n.2xlarge` | no |

Note that these will just be bare AMI machines without any Kafka client or
testing tools installed. This may be added in the future.

## Outputs

| Name | Description |
|------|-------------|
| prometheus | n/a |
| public\_key\_path | n/a |
| redpanda | n/a |
| ssh\_user | n/a |

## Test

## Requirements

You must have Go installed in order to run infrastructure tests.

| Name | Version |
|------|---------|
| go | >1.13 |
| terraform | >0.13.X |

Test the infrastructure with the following command:

`cd test/ && go test `

