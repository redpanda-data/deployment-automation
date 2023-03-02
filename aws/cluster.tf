resource "random_uuid" "cluster" {}

resource "time_static" "timestamp" {}

locals {
  uuid                       = random_uuid.cluster.result
  timestamp                  = time_static.timestamp.unix
  deployment_id              = length(var.deployment_prefix) > 0 ? var.deployment_prefix : "redpanda-${substr(local.uuid, 0, 8)}-${local.timestamp}"
  tiered_storage_bucket_name = "${local.deployment_id}-bucket"

  # tags shared by all instances
  instance_tags = {
    owner : local.deployment_id
    iam_username : trimprefix(data.aws_arn.caller_arn.resource, "user/")
  }

  merged_tags = merge(local.instance_tags, var.tags)
}

resource "aws_iam_policy" "redpanda" {
  count  = var.tiered_storage_enabled ? 1 : 0
  name   = local.deployment_id
  path   = "/"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:*",
          "s3-object-lambda:*",
        ],
        "Resource" : [
          "arn:aws:s3:::${local.tiered_storage_bucket_name}/*"
        ]
      },
    ]
  })
}

resource "aws_iam_role" "redpanda" {
  count              = var.tiered_storage_enabled ? 1 : 0
  name               = local.deployment_id
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Sid       = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy_attachment" "redpanda" {
  count      = var.tiered_storage_enabled ? 1 : 0
  name       = local.deployment_id
  roles      = [aws_iam_role.redpanda[count.index].name]
  policy_arn = aws_iam_policy.redpanda[count.index].arn
}

resource "aws_iam_instance_profile" "redpanda" {
  count = var.tiered_storage_enabled ? 1 : 0
  name  = local.deployment_id
  role  = aws_iam_role.redpanda[count.index].name
}


resource "aws_instance" "redpanda" {
  count                      = var.nodes
  ami                        = coalesce(var.cluster_ami, data.aws_ami.ami.image_id)
  instance_type              = var.instance_type
  key_name                   = aws_key_pair.ssh.key_name
  iam_instance_profile       = var.tiered_storage_enabled ? aws_iam_instance_profile.redpanda[0].name : null
  vpc_security_group_ids     = [aws_security_group.node_sec_group.id]
  placement_group            = var.ha ? aws_placement_group.redpanda-pg[0].id : null
  placement_partition_number = var.ha ? (count.index % aws_placement_group.redpanda-pg[0].partition_count) + 1 : null
  subnet_id                  = var.subnet_id   
  tags                       = merge(
    local.merged_tags,
    {
      Name = "${local.deployment_id}-node-${count.index}",
    }
  )

  connection {
    user        = var.distro_ssh_user[var.distro]
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_ebs_volume" "ebs_volume" {
  count             = var.nodes * var.ec2_ebs_volume_count
  availability_zone = aws_instance.redpanda[*].availability_zone[count.index]
  size              = var.ec2_ebs_volume_size
  type              = var.ec2_ebs_volume_type
  iops              = var.ec2_ebs_volume_iops
  throughput        = var.ec2_ebs_volume_throughput
}

resource "aws_volume_attachment" "volume_attachment" {
  count       = var.nodes * var.ec2_ebs_volume_count
  volume_id   = aws_ebs_volume.ebs_volume[*].id[count.index]
  device_name = var.ec2_ebs_device_names[count.index]
  instance_id = aws_instance.redpanda[*].id[count.index]
}

resource "aws_instance" "prometheus" {
  count                  = var.enable_monitoring ? 1 : 0
  ami                    = coalesce(var.prometheus_ami, data.aws_ami.ami.image_id)
  instance_type          = var.prometheus_instance_type
  key_name               = aws_key_pair.ssh.key_name
  subnet_id              = var.subnet_id   
  vpc_security_group_ids = [aws_security_group.node_sec_group.id]
  tags                   = merge(
    local.merged_tags,
    {
      Name = "${local.deployment_id}-prometheus",
    }
  )

  connection {
    user        = var.distro_ssh_user[var.distro]
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_instance" "client" {
  count                  = var.clients
  ami                    = coalesce(var.client_ami, data.aws_ami.ami.image_id)
  instance_type          = var.client_instance_type
  key_name               = aws_key_pair.ssh.key_name
  subnet_id              = var.subnet_id   
  vpc_security_group_ids = [aws_security_group.node_sec_group.id]
  tags                   = merge(
    local.merged_tags,
    {
      Name = "${local.deployment_id}-client",
    }
  )

  connection {
    user        = var.distro_ssh_user[var.client_distro]
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_security_group" "node_sec_group" {
  name        = "${local.deployment_id}-node-sec-group"
  tags        = local.merged_tags
  description = "redpanda ports"
  vpc_id      = var.vpc_id

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
    description = "Allow anywhere inbound to access the Redpanda Kafka endpoint"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access to the RPC port
  ingress {
    description = "Allow security-group only to access Redpanda RPC endpoint for intra-cluster communication"
    from_port   = 33145
    to_port     = 33145
    protocol    = "tcp"
    self        = true
  }

  # HTTP access to the Admin port
  ingress {
    description = "Allow anywhere inbound to access Redpanda Admin endpoint"
    from_port   = 9644
    to_port     = 9644
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # grafana
  ingress {
    description = "Allow anywhere inbound to access grafana end point for monitoring"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # java client for open messaging benchmark (omb)
  ingress {
    description = "Allow anywhere inbound to access for Open Messaging Benchmark"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # prometheus
  ingress {
    description = "Allow anywhere inbound to access Prometheus end point for monitoring"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # node exporter
  ingress {
    description = "node_exporter access within the security-group for ansible"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    self        = true
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
  tags            = local.merged_tags
  count           = var.ha ? 1 : 0
}


resource "aws_key_pair" "ssh" {
  key_name   = "${local.deployment_id}-key"
  public_key = file(var.public_key_path)
  tags       = local.merged_tags
}

resource "local_file" "hosts_ini" {
  content = templatefile("${path.module}/../templates/hosts_ini.tpl",
    {
      cloud_storage_region       = var.aws_region
      client_public_ips          = aws_instance.client[*].public_ip
      client_private_ips         = aws_instance.client[*].private_ip
      enable_monitoring          = var.enable_monitoring
      monitor_public_ip          = var.enable_monitoring ? aws_instance.prometheus[0].public_ip : ""
      monitor_private_ip         = var.enable_monitoring ? aws_instance.prometheus[0].private_ip : ""
      rack                       = aws_instance.redpanda[*].placement_partition_number
      redpanda_public_ips        = aws_instance.redpanda[*].public_ip
      redpanda_private_ips       = aws_instance.redpanda[*].private_ip
      ssh_user                   = var.distro_ssh_user[var.distro]
      tiered_storage_bucket_name = local.tiered_storage_bucket_name
      tiered_storage_enabled     = var.tiered_storage_enabled
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