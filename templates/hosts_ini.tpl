[redpanda]
%{ for i, ip in redpanda_public_ips ~}
${ ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${redpanda_private_ips[i]} id=${i}
%{ endfor ~}

%{~ if enable_monitoring == true ~}
[monitor]
${ prometheus_public_ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${ prometheus_private_ip } id=0
%{~ endif ~}
