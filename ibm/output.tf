output "redpanda-ips" {
    value = ibm_is_floating_ip.fip.*.address
}

output "monitoring-ips" {
    value = ibm_is_floating_ip.fip_monitoring.*.address
}