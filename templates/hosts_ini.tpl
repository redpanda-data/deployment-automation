[redpanda]
%{ for i, ip in redpanda_public_ips ~}
${ ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${redpanda_private_ips[i]} id=${i}
%{ endfor ~}
%{ if enable_monitoring }

[monitor]
${ monitor_public_ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${ monitor_private_ip }
%{ endif }

[client]
%{ for i, ip in client_public_ips ~}
${ ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${client_private_ips[i]} id=${i}
%{ endfor ~}
