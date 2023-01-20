[redpanda]
%{ for i, ip in redpanda_public_ips ~}
${ ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${redpanda_private_ips[i]}%{ if rack_awareness } rack=${rack[i]}%{ endif }%{ if tiered_storage_enabled } tiered_storage_bucket_name=${tiered_storage_bucket_name} cloud_storage_region=${cloud_storage_region}%{ endif }
%{ endfor ~}
%{ if enable_monitoring }

[monitor]
${ monitor_public_ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${ monitor_private_ip }
%{ endif }

%{ if length(client_public_ips) > 0 }
[client]
%{ for i, ip in client_public_ips ~}
${ ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${client_private_ips[i]} id=${i}
%{ endfor ~}
%{ endif }
