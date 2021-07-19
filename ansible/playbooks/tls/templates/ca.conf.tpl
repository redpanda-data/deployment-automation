# OpenSSL CA configuration file
[ ca ]
default_ca = local_ca

[ local_ca ]
dir              = {{ root_ca_dir }}
database         = $dir/index.txt
serial           = $dir/serial.txt
default_days     = 730
default_md       = sha256
copy_extensions  = copy
unique_subject   = no

# Used to create the CA certificate.
[ req ]
prompt             = no
distinguished_name = distinguished_name
x509_extensions    = extensions

[ root_ca_distinguished_name ]
commonName              = Test TLS CA
stateOrProvinceName     = NY
countryName             = US
emailAddress            = hi@vectorized.io
organizationName        = Vectorized
organizationalUnitName  = Vectorized Test

[ distinguished_name ]
organizationName = Vectorized
commonName       = Vectorized Test CA

[ extensions ]
keyUsage         = critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign
basicConstraints = critical,CA:true,pathlen:1

# Common policy for nodes and users.
[ signing_policy ]
organizationName = supplied
commonName       = optional

# Used to sign node certificates.
[ signing_node_req ]
keyUsage         = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth,clientAuth

# Used to sign client certificates.
[ signing_client_req ]
keyUsage         = critical,digitalSignature,keyEncipherment
extendedKeyUsage = clientAuth
