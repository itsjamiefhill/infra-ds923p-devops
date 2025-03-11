# Self-Signed Certificates for HomeLab DevOps Platform

This document provides detailed information about creating, managing, and using self-signed certificates for the HomeLab DevOps Platform on Synology DS923+.

## Table of Contents

1. [Overview](#overview)
2. [Creating a Self-Signed Certificate](#creating-a-self-signed-certificate)
3. [Setting Up a Local Certificate Authority](#setting-up-a-local-certificate-authority)
4. [Certificate Distribution](#certificate-distribution)
5. [Configuring Traefik](#configuring-traefik)
6. [Configuring Docker](#configuring-docker)
7. [Certificate Renewal](#certificate-renewal)
8. [Troubleshooting](#troubleshooting)

## Overview

Since the HomeLab DevOps Platform operates within your local network without external access, self-signed certificates provide a secure way to enable HTTPS for your services without the need for public Certificate Authorities like Let's Encrypt.

Benefits of self-signed certificates in this context:
- No external dependencies
- No need for domain verification
- No rate limits or renewal concerns
- Complete control over certificate parameters
- Works without internet access

## Creating a Self-Signed Certificate

### Basic Self-Signed Certificate

For a simple setup, create a wildcard certificate for all services:

```bash
# Create directory for certificates
mkdir -p /volume1/docker/nomad/config/certs

# Generate a self-signed wildcard certificate
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /volume1/docker/nomad/config/certs/homelab.key \
  -out /volume1/docker/nomad/config/certs/homelab.crt \
  -subj "/CN=*.homelab.local" \
  -addext "subjectAltName=DNS:*.homelab.local,DNS:homelab.local"

# Copy to volume directory for mounting
mkdir -p /volume1/docker/nomad/volumes/certificates
cp /volume1/docker/nomad/config/certs/homelab.* /volume1/docker/nomad/volumes/certificates/
```

This creates a certificate valid for 10 years (3650 days) that covers all `*.homelab.local` subdomains.

### Certificate Parameters

You can adjust these parameters to suit your needs:

- **Key Size**: Increase to 4096 bits for stronger security (at the cost of slightly more CPU)
- **Validity Period**: Adjust the days parameter (3650 = 10 years)
- **Subject Information**: Add additional details like organization or location:
  ```bash
  -subj "/CN=*.homelab.local/O=HomeLab DevOps/C=US/ST=State/L=City"
  ```
- **Subject Alternative Names**: Add all specific domains you plan to use:
  ```bash
  -addext "subjectAltName=DNS:*.homelab.local,DNS:homelab.local,DNS:consul.homelab.local,DNS:vault.homelab.local"
  ```

## Setting Up a Local Certificate Authority

For a more robust setup, create your own Certificate Authority (CA) and issue certificates from it:

### 1. Create a Root CA

```bash
# Create directories
mkdir -p /volume1/docker/nomad/config/ca/{certs,private,newcerts,crl}
touch /volume1/docker/nomad/config/ca/index.txt
echo 1000 > /volume1/docker/nomad/config/ca/serial

# Create CA configuration file
cat > /volume1/docker/nomad/config/ca/openssl.cnf << EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /volume1/docker/nomad/config/ca
certs             = \$dir/certs
crl_dir           = \$dir/crl
database          = \$dir/index.txt
new_certs_dir     = \$dir/newcerts
certificate       = \$dir/certs/ca.crt
serial            = \$dir/serial
crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/ca.crl
private_key       = \$dir/private/ca.key
x509_extensions   = usr_cert
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 3650
default_crl_days  = 30
default_md        = sha256
preserve          = no
policy            = policy_match

[ policy_match ]
countryName             = optional
stateOrProvinceName     = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 2048
default_keyfile     = privkey.pem
distinguished_name  = req_distinguished_name
attributes          = req_attributes
x509_extensions     = v3_ca
string_mask         = utf8only

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

[ req_attributes ]
challengePassword       = A challenge password
unstructuredName        = An optional company name

[ usr_cert ]
basicConstraints = CA:FALSE
nsCertType = client, server
nsComment = "OpenSSL Generated Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

# Generate CA private key
openssl genrsa -out /volume1/docker/nomad/config/ca/private/ca.key 4096

# Create root CA certificate
openssl req -x509 -new -nodes -key /volume1/docker/nomad/config/ca/private/ca.key \
  -sha256 -days 3650 -out /volume1/docker/nomad/config/ca/certs/ca.crt \
  -subj "/CN=HomeLab Root CA/O=HomeLab DevOps/C=US" \
  -config /volume1/docker/nomad/config/ca/openssl.cnf \
  -extensions v3_ca
```

### 2. Generate a Certificate Signing Request (CSR)

```bash
# Create private key
openssl genrsa -out /volume1/docker/nomad/config/certs/homelab.key 2048

# Create CSR
openssl req -new -key /volume1/docker/nomad/config/certs/homelab.key \
  -out /volume1/docker/nomad/config/certs/homelab.csr \
  -subj "/CN=*.homelab.local/O=HomeLab DevOps"
```

### 3. Sign the CSR with Your CA

Create an extensions file for the wildcard certificate:

```bash
cat > /volume1/docker/nomad/config/certs/homelab.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.homelab.local
DNS.2 = homelab.local
EOF

# Sign the certificate
openssl x509 -req -in /volume1/docker/nomad/config/certs/homelab.csr \
  -CA /volume1/docker/nomad/config/ca/certs/ca.crt \
  -CAkey /volume1/docker/nomad/config/ca/private/ca.key \
  -CAcreateserial \
  -out /volume1/docker/nomad/config/certs/homelab.crt \
  -days 3650 -sha256 \
  -extfile /volume1/docker/nomad/config/certs/homelab.ext

# Copy to volume directory for mounting
cp /volume1/docker/nomad/config/certs/homelab.* /volume1/docker/nomad/volumes/certificates/
cp /volume1/docker/nomad/config/ca/certs/ca.crt /volume1/docker/nomad/volumes/certificates/
```

## Certificate Distribution

For your certificates to be trusted across your devices, you need to distribute and install them:

### Windows

1. **Export the certificate** from your Synology:
   ```bash
   # If using just self-signed cert
   scp your-username@synology-ip:/volume1/docker/nomad/config/certs/homelab.crt .
   
   # If using CA
   scp your-username@synology-ip:/volume1/docker/nomad/config/ca/certs/ca.crt .
   ```

2. **Install the certificate**:
   - Double-click the certificate file
   - Click "Install Certificate"
   - Select "Local Machine" and click Next
   - Select "Place all certificates in the following store"
   - Click "Browse" and select "Trusted Root Certification Authorities"
   - Click "Next" and "Finish"

### macOS

1. **Export the certificate** (as above)
2. **Install the certificate**:
   - Double-click the certificate file to open it in Keychain Access
   - Add to the System keychain
   - Find the certificate, double-click it
   - Expand the "Trust" section
   - Set "When using this certificate" to "Always Trust"

### Linux

1. **Export the certificate** (as above)
2. **Install the certificate**:
   ```bash
   sudo cp homelab.crt /usr/local/share/ca-certificates/
   sudo update-ca-certificates
   ```

### iOS/Android

1. **Email the certificate** to yourself or make it available via a web server
2. **Open the certificate** on the device and follow the prompts to install it
3. On iOS, go to Settings > General > About > Certificate Trust Settings to enable it

## Configuring Traefik

Configure Traefik to use your self-signed certificates:

```hcl
# In traefik.hcl job definition
volume "certificates" {
  type = "host"
  read_only = true
  source = "certificates"
}

task "traefik" {
  // ...

  volume_mount {
    volume = "certificates"
    destination = "/etc/traefik/certs"
    read_only = true
  }

  template {
    data = <<EOF
// ... other configuration ...

[tls]
  [[tls.certificates]]
    certFile = "/etc/traefik/certs/homelab.crt"
    keyFile = "/etc/traefik/certs/homelab.key"
EOF
    destination = "local/traefik.toml"
  }
  
  // ...
}
```

If you're using a CA, you can also include the CA certificate:

```
[tls]
  [[tls.certificates]]
    certFile = "/etc/traefik/certs/homelab.crt"
    keyFile = "/etc/traefik/certs/homelab.key"
    
  [tls.options.default]
    [tls.options.default.clientAuth]
      caFiles = ["/etc/traefik/certs/ca.crt"]
```

## Configuring Docker

For the Docker Registry to work with self-signed certificates, configure Docker to trust them:

```bash
# Create directory for certificates
sudo mkdir -p /etc/docker/certs.d/registry.homelab.local:5000

# Copy self-signed certificate
sudo cp /volume1/docker/nomad/config/certs/homelab.crt /etc/docker/certs.d/registry.homelab.local:5000/ca.crt

# If using a CA, use the CA certificate instead
# sudo cp /volume1/docker/nomad/config/ca/certs/ca.crt /etc/docker/certs.d/registry.homelab.local:5000/ca.crt

# Restart Docker
sudo systemctl restart docker
```

## Certificate Renewal

Self-signed certificates do not automatically renew. You'll need to manually replace them before they expire, or set up a scheduled task:

```bash
# Create a renewal script
cat > /volume1/docker/nomad/scripts/renew-certificates.sh << EOF
#!/bin/bash
# Check certificate expiration
EXPIRY=\$(openssl x509 -enddate -noout -in /volume1/docker/nomad/config/certs/homelab.crt | cut -d= -f2)
EXPIRY_EPOCH=\$(date -d "\$EXPIRY" +%s)
NOW_EPOCH=\$(date +%s)
DAYS_REMAINING=\$(( (\$EXPIRY_EPOCH - \$NOW_EPOCH) / 86400 ))

# If less than 30 days remaining, renew certificate
if [ \$DAYS_REMAINING -lt 30 ]; then
  echo "Certificate expires in \$DAYS_REMAINING days. Renewing..."
  
  # Generate new certificate
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \\
    -keyout /volume1/docker/nomad/config/certs/homelab.key \\
    -out /volume1/docker/nomad/config/certs/homelab.crt \\
    -subj "/CN=*.homelab.local" \\
    -addext "subjectAltName=DNS:*.homelab.local,DNS:homelab.local"
  
  # Copy to volume directory
  cp /volume1/docker/nomad/config/certs/homelab.* /volume1/docker/nomad/volumes/certificates/
  
  # Restart Traefik to pick up new certificate
  nomad job restart traefik
  
  echo "Certificate renewed successfully."
else
  echo "Certificate valid for \$DAYS_REMAINING more days. No action needed."
fi
EOF

chmod +x /volume1/docker/docker/nomad/scripts/renew-certificates.sh

# Create a scheduled task in Synology DSM
# Control Panel > Task Scheduler > Create > Scheduled Task > User-defined script
# Set to run monthly
# Task: bash /volume1/docker/nomad/scripts/renew-certificates.sh
```

## Troubleshooting

### Certificate Not Trusted

If browsers show "Certificate not trusted" errors:

1. **Verify the certificate is installed** in the browser's trust store
2. **Check the certificate details** to ensure domains match
3. **Clear browser cache** and restart the browser
4. **Verify certificate file format** is correct (PEM format)

### Certificate Validation Issues

If certificate validation fails:

```bash
# Check certificate details
openssl x509 -in /volume1/docker/nomad/config/certs/homelab.crt -text -noout

# Verify certificate matches private key
openssl x509 -noout -modulus -in /volume1/docker/nomad/config/certs/homelab.crt | openssl md5
openssl rsa -noout -modulus -in /volume1/docker/nomad/config/certs/homelab.key | openssl md5
# The outputs should match
```

### Name Mismatch Errors

If you see "name does not match certificate" errors:

1. **Check Subject Alternative Names** (SANs):
   ```bash
   openssl x509 -in /volume1/docker/nomad/config/certs/homelab.crt -text -noout | grep -A1 "Subject Alternative Name"
   ```

2. **Ensure hostname resolution** is correctly configured:
   ```bash
   cat /etc/hosts | grep homelab
   ```

3. **Create a new certificate** with correct SANs if needed

### Docker Registry Certificate Issues

If you cannot push/pull from the registry:

1. **Verify certificate installation**:
   ```bash
   ls -la /etc/docker/certs.d/registry.homelab.local:5000/
   ```

2. **Check Docker daemon logs**:
   ```bash
   journalctl -u docker
   ```

3. **Test registry connection manually**:
   ```bash
   curl -v https://registry.homelab.local:5000/v2/
   ```