output "redpanda" {
  value = {
    for instance in aws_instance.redpanda :
    instance.public_ip => instance.private_ip...
  }
}

output "redpanda_id" {
  value = {
    for instance in aws_instance.redpanda :
    "instance_id" => instance.id...
  }
}

output "prometheus" {
  value = {
    for instance in aws_instance.prometheus :
    instance.public_ip => instance.private_ip...
  }
}

output "prometheus_id" {
  value = {
    for instance in aws_instance.prometheus :
    "instance_id" => instance.id...
  }
}

output "client" {
  value = {
    for instance in aws_instance.client :
    instance.public_ip => instance.private_ip...
  }
}

output "client_id" {
  value = {
    for instance in aws_instance.client :
    "instance_id" => instance.id...
  }
}

output "ssh_user" {
  value = var.distro_ssh_user[var.distro]
}

output "public_key_path" {
  value = var.public_key_path
}

output "node_details" {
  value = local.node_details
}