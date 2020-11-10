[redpanda]
%{ for i, instance in redpanda ~}
${ instance.public_ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${instance.private_ip} id=${i}
%{ endfor ~}

%{~ if enable_monitoring == true ~}
[monitor]
${ prometheus.public_ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${ prometheus.private_ip } id=0
%{~ endif ~}
