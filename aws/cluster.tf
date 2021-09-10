resource "random_uuid" "cluster" {}

locals {
  timestamp = timestamp()
  uuid = random_uuid.cluster.result
  deployment_id = "redpanda-${random_uuid.cluster.result}-${local.timestamp}"
}

resource "aws_instance" "redpanda" {
  count                  = var.nodes
  ami                    = var.distro_ami[var.distro]
  instance_type          = var.instance_type
  key_name               = aws_key_pair.ssh.key_name
  vpc_security_group_ids = [aws_security_group.node_sec_group.id]
  tags = {
    owner : local.deployment_id
  }

  connection {
    user        = var.distro_ssh_user[var.distro]
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }
}

resource "aws_instance" "prometheus" {
  count                  = var.enable_monitoring ? 1 : 0
  ami                    = var.distro_ami[var.distro]
  instance_type          = var.prometheus_instance_type
  key_name               = aws_key_pair.ssh.key_name
  vpc_security_group_ids = [aws_security_group.node_sec_group.id]
  tags = {
    owner : local.deployment_id
  }

  connection {
    user        = var.distro_ssh_user[var.distro]
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }
}

resource "aws_instance" "client" {
  count                 = var.clients
  ami                   = var.distro_ami[var.client_distro]
  instance_type         = var.client_instance_type
  key_name              = aws_key_pair.ssh.key_name
  vpc_security_group_ids = [aws_security_group.node_sec_group.id]
  tags = {
    owner : local.deployment_id
  }

  connection {
    user        = var.distro_ssh_user[var.client_distro]
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }
}

resource "aws_security_group" "node_sec_group" {
  name = "${local.deployment_id}-node-sec-group"
  tags = {
    owner : local.deployment_id
  }
  description = "redpanda ports"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from anywhere to port 9092
  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access to the RPC port
  ingress {
    from_port   = 33145
    to_port     = 33145
    protocol    = "tcp"
    self        = true
  }

  # HTTP access to the Admin port
  ingress {
    from_port   = 9644
    to_port     = 9644
    protocol    = "tcp"
    self        = true
  }

  # grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # node exporter
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    self        = true
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "ssh" {
  key_name   = "${local.deployment_id}-key"
  public_key = file(var.public_key_path)
}

resource "local_file" "hosts_ini" {
  content = templatefile("${path.module}/../templates/hosts_ini.tpl",
    {
      redpanda_public_ips   = aws_instance.redpanda.*.public_ip
      redpanda_private_ips  = aws_instance.redpanda.*.private_ip
      monitor_public_ip  = var.enable_monitoring ? aws_instance.prometheus[0].public_ip : ""
      monitor_private_ip = var.enable_monitoring ? aws_instance.prometheus[0].private_ip : ""
      ssh_user              = var.distro_ssh_user[var.distro]
      enable_monitoring     = var.enable_monitoring
      client_public_ips     = aws_instance.client.*.public_ip
      client_private_ips     = aws_instance.client.*.private_ip
    }
  )
  filename = "${path.module}/../hosts.ini"
}
