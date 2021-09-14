variable "aws_region" {
  description = "The AWS region to deploy the infrastructure on"
  default     = "us-west-2"
}

variable "nodes" {
  description = "The number of nodes to deploy"
  type        = number
  default     = "3"
}

variable "distro" {
  description = "The default distribution to base the cluster on"
  default     = "ubuntu-focal"
}

variable "instance_type" {
  description = "Default redpanda instance type to create"
  default     = "i3.2xlarge"
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

variable "public_key_path" {
  description = "The public key used to ssh to the hosts"
  default     = "~/.ssh/id_rsa.pub"
}

variable "distro_ami" {
  type = map(string)
  default = {
    # https://wiki.debian.org/Cloud/AmazonEC2Image/
    "debian-stretch" = "ami-072ad3956e05c814c"
    "debian-buster"  = "ami-0f7939d313699273c"

    # https://alt.fedoraproject.org/cloud/
    "fedora-31" = "ami-0e82cc6ce8f393d4b"
    "fedora-32" = "ami-020405ee5d5747724"

    # https://cloud-images.ubuntu.com/locator/ec2/
    "ubuntu-focal"  = "ami-02c45ea799467b51b"
    "ubuntu-bionic" = "ami-0c1ab2d66f996cd4b"
    # non-LTS for development
    "ubuntu-hirsute" = "ami-035649ffeb04ce758"

    # https://us-west-2.console.aws.amazon.com/ec2/v2/home?region=us-west-2#LaunchInstanceWizard:
    "rhel-8"         = "ami-087c2c50437d0b80d"
    "amazon-linux-2" = "ami-01ce4793a2f45922e"
  }
}

variable "distro_ssh_user" {
  description = "The default user used by the AWS AMIs"
  type        = map(string)
  default = {
    "debian-stretch" = "admin"
    "debian-buster"  = "admin"
    "fedora-31"      = "fedora"
    "fedora-32"      = "fedora"
    "ubuntu-bionic"  = "ubuntu"
    "ubuntu-focal"   = "ubuntu"
    "ubuntu-hirsute" = "ubuntu"
    "rhel-8"         = "ec2-user"
    "amazon-linux-2" = "ec2-user"
  }
}
