output "redpanda" {
  value = {
    for instance in aws_instance.redpanda :
    instance.public_ip => instance.private_ip
  }
}

output "prometheus" {
  value = {
    for instance in aws_instance.prometheus :
    instance.public_ip => instance.private_ip
  }
}

output "client" {
  value = {
    for instance in aws_instance.client :
    instance.public_ip => instance.private_ip
  }
}

output "ssh_user" {
  value = var.distro_ssh_user[var.distro]
}

output "public_key_path" {
  value = var.public_key_path
}
