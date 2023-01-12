resource "random_uuid" "cluster" {}

resource "time_static" "timestamp" {}

locals {
  uuid          = random_uuid.cluster.result
  timestamp     = time_static.timestamp.rfc3339
  deployment_id = "redpanda-${local.uuid}-${local.timestamp}"

  # tags shared by all instances
  instance_tags = {
    owner        : local.deployment_id
    iam_username : trimprefix(data.aws_arn.caller_arn.resource, "user/")
  }
}

resource "aws_instance" "redpanda" {
  count                      = var.nodes
  ami                        = var.distro_ami[var.distro]
  instance_type              = var.instance_type
  key_name                   = aws_key_pair.ssh.key_name
  vpc_security_group_ids     = [aws_security_group.node_sec_group.id]
  placement_group            = var.ha ? aws_placement_group.redpanda-pg[0].id : null
  placement_partition_number = var.ha ? (count.index % aws_placement_group.redpanda-pg[0].partition_count) + 1 : null
  tags                       = local.instance_tags

  connection {
    user        = var.distro_ssh_user[var.distro]
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }
}

resource "aws_ebs_volume" "ebs_volume" {
  count             = "${var.nodes * var.ec2_ebs_volume_count}"
  availability_zone = "${element(aws_instance.redpanda.*.availability_zone, count.index)}"
  size              = "${var.ec2_ebs_volume_size}"
  type              = "${var.ec2_ebs_volume_type}"
  iops              = "${var.ec2_ebs_volume_iops}"
  throughput        = "${var.ec2_ebs_volume_throughput}"
}

resource "aws_volume_attachment" "volume_attachment" {
  count       = "${var.nodes * var.ec2_ebs_volume_count}"
  volume_id   = "${aws_ebs_volume.ebs_volume.*.id[count.index]}"
  device_name = "${element(var.ec2_ebs_device_names, count.index)}"
  instance_id = "${element(aws_instance.redpanda.*.id, count.index)}"
}

resource "aws_instance" "prometheus" {
  count                  = var.enable_monitoring ? 1 : 0
  ami                    = var.distro_ami[var.distro]
  instance_type          = var.prometheus_instance_type
  key_name               = aws_key_pair.ssh.key_name
  vpc_security_group_ids = [aws_security_group.node_sec_group.id]
  tags                   = local.instance_tags

  connection {
    user        = var.distro_ssh_user[var.distro]
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }
}

resource "aws_instance" "client" {
  count                  = var.clients
  ami                    = var.distro_ami[var.client_distro]
  instance_type          = var.client_instance_type
  key_name               = aws_key_pair.ssh.key_name
  vpc_security_group_ids = [aws_security_group.node_sec_group.id]
  tags                   = local.instance_tags

  connection {
    user        = var.distro_ssh_user[var.client_distro]
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }
}

resource "aws_security_group" "node_sec_group" {
  name        = "${local.deployment_id}-node-sec-group"
  tags        = local.instance_tags
  description = "redpanda ports"

  # SSH access from anywhere
  ingress {
    description = "Allow anywhere inbound to ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from anywhere to port 9092
  ingress {
    description = "Allow anywhere to access the Redpanda Kafka endpoint"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access to the RPC port
  ingress {
    description = "Allow security-group only to access Redpanda RPC endpoint for intra-cluster communication"
    from_port = 33145
    to_port   = 33145
    protocol  = "tcp"
    self      = true
  }

  # HTTP access to the Admin port
  ingress {
    description = "Allow anywhere to access Redpanda Admin endpoint"
    from_port   = 9644
    to_port     = 9644
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # grafana
  ingress {
    description = "Allow anywhere to access grafana end point for monitoring"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # java client for open messaging benchmark (omb)
  ingress {
    description = "Allow anywhere to access for Open Messaging Benchmark"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # prometheus
  ingress {
    description = "Allow anywhere to access Prometheus end point for monitoring"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # node exporter
  ingress {
    description = "node_exporter access within the security-group for ansible"
    from_port = 9100
    to_port   = 9100
    protocol  = "tcp"
    self      = true
  }

  # outbound internet access
  egress {
    description = "Allow all outbound Internet access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_placement_group" "redpanda-pg" {
  name            = "redpanda-pg"
  strategy        = "partition"
  partition_count = 3
  tags            = local.instance_tags
  count           = var.ha ? 1 : 0
}


resource "aws_key_pair" "ssh" {
  key_name   = "${local.deployment_id}-key"
  public_key = file(var.public_key_path)
}

resource "local_file" "hosts_ini" {
  content = templatefile("${path.module}/../templates/hosts_ini.tpl",
    {
      redpanda_public_ips  = aws_instance.redpanda.*.public_ip
      redpanda_private_ips = aws_instance.redpanda.*.private_ip
      monitor_public_ip    = var.enable_monitoring ? aws_instance.prometheus[0].public_ip : ""
      monitor_private_ip   = var.enable_monitoring ? aws_instance.prometheus[0].private_ip : ""
      ssh_user             = var.distro_ssh_user[var.distro]
      enable_monitoring    = var.enable_monitoring
      client_public_ips    = aws_instance.client.*.public_ip
      client_private_ips   = aws_instance.client.*.private_ip
      rack                 = aws_instance.redpanda.*.placement_partition_number
    }
  )
  filename = "${path.module}/../hosts.ini"
}

# we extract the IAM username by getting the caller identity as an ARN
# then extracting the resource protion, which gives something like 
# user/travis.downs, and finally we strip the user/ part to use as a tag
data "aws_caller_identity" "current" {}

data "aws_arn" "caller_arn" {
  arn = data.aws_caller_identity.current.arn
}
