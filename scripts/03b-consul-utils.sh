#!/bin/bash
# 03b-consul-utils.sh
# Directory and data functions for Consul deployment (Docker-only version)

# Prepare Consul data directory
prepare_consul_directory() {
  log "Setting up Consul data directory for Synology..."
  
  # Check if directory exists, create if not
  if [ ! -d "${DATA_DIR}/consul_data" ]; then
    log "Creating Consul data directory..."
    mkdir -p "${DATA_DIR}/consul_data" 2>/dev/null || sudo mkdir -p "${DATA_DIR}/consul_data"
    
    # Attempt to set permissions using sudo
    sudo chmod 777 "${DATA_DIR}/consul_data" 2>/dev/null || warn "Failed to set directory permissions with sudo"
    
    if [ ! -w "${DATA_DIR}/consul_data" ]; then
      warn "Directory is not writable. This may cause issues with data persistence."
    else
      success "Consul data directory created and is writable"
    fi
  else
    # Ensure permissions are correct for existing directory
    log "Ensuring proper permissions on existing consul_data directory..."
    sudo chmod 777 "${DATA_DIR}/consul_data" 2>/dev/null || warn "Failed to update directory permissions with sudo"
    
    if [ ! -w "${DATA_DIR}/consul_data" ]; then
      warn "Directory is not writable. This may cause issues with data persistence."
    else
      log "Consul data directory exists and is writable"
    fi
  fi
}

# Function to prepare SSL certificates for Consul with self-signed certificates
prepare_consul_ssl() {
  log "Preparing SSL certificates for Consul..."
  
  # Check if SSL for Consul is enabled in config
  if [ "${CONSUL_ENABLE_SSL:-false}" != "true" ]; then
    log "Consul SSL is not enabled in configuration. Skipping."
    return 0
  fi
  
  # Create directory for Consul certificates
  sudo mkdir -p "${DATA_DIR}/certificates/consul" 2>/dev/null
  
  # Check if we already have self-signed certificates
  if [ -f "${DATA_DIR}/certificates/consul/ca.pem" ] && \
     [ -f "${DATA_DIR}/certificates/consul/server.pem" ] && \
     [ -f "${DATA_DIR}/certificates/consul/server-key.pem" ]; then
    log "Self-signed certificates already exist. Using existing certificates."
  else
    log "Generating new self-signed certificates for Consul..."
    
    # Check if OpenSSL is available
    if ! command -v openssl &> /dev/null; then
      warn "OpenSSL is not installed. Cannot generate certificates."
      CONSUL_ENABLE_SSL="false"
      return 1
    fi
    
    # Get the current IP address using standardized function
    SYNOLOGY_IP=$(get_primary_ip)
    if [[ ! $SYNOLOGY_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      log "IP address format invalid: '$SYNOLOGY_IP'. Using 127.0.0.1 as fallback."
      SYNOLOGY_IP="127.0.0.1"
    fi
    
    log "Using IP address for certificates: ${SYNOLOGY_IP}"
    
    # Use datacenter from config or default to dc1
    DATACENTER=${CONSUL_DATACENTER:-dc1}
    log "Using datacenter for certificates: ${DATACENTER}"
    
    # Create a temporary directory for certificate generation
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Generate CA key and certificate
    log "Generating CA key and certificate..."
    openssl genrsa -out ca.key 2048
    openssl req -x509 -new -nodes -key ca.key -sha256 -days 1825 -out ca.pem \
      -subj "/C=US/ST=State/L=City/O=HomeLab/CN=Consul CA"
    
    # Generate server key
    log "Generating server key..."
    openssl genrsa -out server.key 2048
    
    # Create config file for SAN support
    cat > openssl.cnf << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=State
L=City
O=HomeLab
CN=${CONSUL_HOST}

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${CONSUL_HOST}
DNS.2 = consul.service.consul
DNS.3 = server.${DOMAIN}
DNS.4 = server.${DATACENTER}.consul
DNS.5 = localhost
IP.1 = 127.0.0.1
IP.2 = ${SYNOLOGY_IP}
EOF
    
    # Generate Certificate Signing Request (CSR)
    log "Generating Certificate Signing Request..."
    openssl req -new -key server.key -out server.csr -config openssl.cnf
    
    # Generate server certificate using CA with extensions from config
    log "Generating server certificate..."
    openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
      -out server.pem -days 1825 -sha256 -extensions v3_req -extfile openssl.cnf
    
    # Verify the certificate
    log "Verifying certificate..."
    openssl x509 -in server.pem -text -noout | grep "Subject Alternative Name" -A1 || true
    
    # Copy generated files to the right location
    log "Copying certificates to ${DATA_DIR}/certificates/consul/..."
    sudo cp ca.pem "${DATA_DIR}/certificates/consul/"
    sudo cp server.pem "${DATA_DIR}/certificates/consul/"
    sudo cp server.key "${DATA_DIR}/certificates/consul/server-key.pem"
    
    # Set appropriate permissions
    sudo chmod 644 "${DATA_DIR}/certificates/consul/ca.pem"
    sudo chmod 644 "${DATA_DIR}/certificates/consul/server.pem"
    sudo chmod 644 "${DATA_DIR}/certificates/consul/server-key.pem"
    
    # Ensure directory permissions
    sudo chmod 755 "${DATA_DIR}/certificates/consul"
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${TEMP_DIR}"
    
    success "Self-signed certificates generated and installed"
  fi
  
  # Create TLS configuration for Consul
  sudo mkdir -p "${CONFIG_DIR}/consul" 2>/dev/null
  sudo chmod 755 "${CONFIG_DIR}/consul"
  
  # Create a more browser-friendly TLS configuration that enables HTTPS interface
  cat > /tmp/tls.json << EOF
{
  "verify_incoming": false,
  "verify_outgoing": true,
  "verify_server_hostname": true,
  "ca_file": "/consul/config/certs/ca.pem",
  "cert_file": "/consul/config/certs/server.pem",
  "key_file": "/consul/config/certs/server-key.pem",
  "auto_encrypt": {
    "allow_tls": true
  },
  "ports": {
    "http": -1,
    "https": ${CONSUL_HTTP_PORT}
  },
  "datacenter": "${CONSUL_DATACENTER:-dc1}"
}
EOF

  # Use sudo to copy the file and set permissions
  sudo cp /tmp/tls.json "${CONFIG_DIR}/consul/tls.json"
  sudo chmod 644 "${CONFIG_DIR}/consul/tls.json"
  rm /tmp/tls.json
  
  log "SSL configuration complete with self-signed certificates"
  success "TLS configuration created for Consul"
  return 0
}