[redpanda]
%{ for i, ip in redpanda_public_ips ~}
${ ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${redpanda_private_ips[i]} id=${i}
%{ endfor ~}

[monitor]
${ monitor_public_ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${ monitor_private_ip }
