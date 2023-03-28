# OpenSSL node configuration file
[ req ]
prompt=no
distinguished_name = distinguished_name
req_extensions = extensions

[ distinguished_name ]
organizationName = Vectorized

[ extensions ]
subjectAltName = critical,DNS:{{ansible_hostname}},DNS:{{ansible_fqdn}},IP:{{inventory_hostname}},IP:{{private_ip}}
