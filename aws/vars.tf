variable "aws_region" {
  description = "The AWS region to deploy the infrastructure on"
  default     = "us-west-2"
}

variable "nodes" {
  description = "The number of nodes to deploy"
  type        = number
  default     = "3"
}

variable "ha" {
  description = "Whether to use placement groups to create an HA topology"
  type        = bool
  default     = false
}

variable "distro" {
  description = "The default distribution to base the cluster on"
  default     = "ubuntu-focal"
}

variable "instance_type" {
  description = "Default redpanda instance type to create"
  default     = "i3.2xlarge"
}

## It is important that device names do not get duplicated on hosts, in rare circumstances the choice of nodes * volumes can result in a factor that causes duplication. Modify this field so there is not a common factor.
## Please pr a more elegant solution if you have one.
variable "ec2_ebs_device_names" {
  description = "Device names for EBS volumes"
  default = [
    "/dev/xvdba",
    "/dev/xvdbb",
    "/dev/xvdbc",
    "/dev/xvdbd",
    "/dev/xvdbe",
    "/dev/xvdbf",
    "/dev/xvdbg",
    "/dev/xvdbh",
    "/dev/xvdbi",
    "/dev/xvdbj",
    "/dev/xvdbk",
    "/dev/xvdbl",
    "/dev/xvdbm",
    "/dev/xvdbn",
    "/dev/xvdbo",
    "/dev/xvdbp",
    "/dev/xvdbq",
    "/dev/xvdbr",
    "/dev/xvdbs",
    "/dev/xvdbt",
    "/dev/xvdbu",
    "/dev/xvdbv",
    "/dev/xvdbw",
    "/dev/xvdbx",
    "/dev/xvdby",
    "/dev/xvdbz"
  ]
}

variable "ec2_ebs_volume_count" {
  description = "Number of EBS volumes to attach to each Redpanda node"
  default = 0
}

variable "ec2_ebs_volume_type" {
  description = "EBS Volume Type (gp3 recommended for performance)"
  default = "gp3"
}

variable "ec2_ebs_volume_iops" {
  description = "IOPs for GP3 Volumes"
  default = 16000
}

variable "ec2_ebs_volume_size" {
  description = "Size of each EBS volume"
  default = 100
}

variable "ec2_ebs_volume_throughput" {
  description = "Throughput per volume in MiB"
  default = 250
}

variable "client_instance_type" {
  description = "Default client instance type to create"
  default     = "m5n.2xlarge"
}

variable "prometheus_instance_type" {
  description = "Instant type of the prometheus/grafana node"
  default     = "c5.2xlarge"
}

variable "enable_monitoring" {
  description = "Setup a prometheus/grafana instance"
  type        = bool
  default     = true
}

variable "clients" {
  description = "Number of kafka client hosts to set up, if any."
  type        = number
  default     = 0
}

variable "client_distro" {
  description = "Linux distribution to use for clients."
  default     = "ubuntu-focal"
}

variable "client_architecture" {
  description = "Architecture used for selecting the AMI - change this if using ARM based instances"
  default     = "x86_64"
}

variable "cluster_ami" {
  description = "AMI for Redpanda broker nodes (if not set, will select based on the client_distro variable"
  default     = null
}

variable "prometheus_ami" {
  description = "AMI for prometheus nodes (if not set, will select based on the client_distro variable"
  default     = null
}

variable "client_ami" {
  description = "AMI for Redpanda client nodes (if not set, will select based on the client_distro variable"
  default     = null
}

variable "public_key_path" {
  description = "The public key used to ssh to the hosts"
  default     = "~/.ssh/id_rsa.pub"
}

data "aws_ami" "ami" {
    most_recent = true

    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*", "Fedora-Cloud-Base-*.x86_64-hvm-us-west-2-gp2-0", "debian-*-amd64-*", "debian-*-hvm-x86_64-gp2-*'", "amzn2-ami-hvm-2.0.*.0-x86_64-gp2", "RHEL*HVM-*-x86_64*Hourly2-GP2"]
    }

    filter {
        name  = "architecture"
        values = [var.client_architecture]
    }

    filter {
        name = "name"
        values = ["*${var.distro}*"]
    }

    filter {
        name   = "virtualization-type"
        values = ["hvm"]
    }

    owners = ["099720109477", "125523088429", "136693071363", "379101102735", "137112412989", "309956199498"] # Canonical, Fedora, Debian (new), Debian (old), Amazon, RedHat
}

variable "distro_ssh_user" {
  description = "The default user used by the AWS AMIs"
  type        = map(string)
  default = {
    "debian-stretch" = "admin"
    "debian-buster"  = "admin"
    "debian-10"      = "admin"
    "debian-11"      = "admin"
    "fedora-31"      = "fedora"
    "fedora-32"      = "fedora"
    #"Fedora-Cloud-Base-36" = "fedora"
    #"Fedora-Cloud-Base-37" = "fedora"
    "ubuntu-bionic"  = "ubuntu"
    "ubuntu-focal"   = "ubuntu"
    "ubuntu-hirsute" = "ubuntu"
    "ubuntu-jammy"   = "ubuntu"
    "ubuntu-kinetic" = "ubuntu"
    "RHEL-8"         = "ec2-user"
    #"RHEL-9"        = "ec2-user"
    "amazon-linux-2" = "ec2-user"
  }
}
