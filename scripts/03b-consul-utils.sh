#!/bin/bash
# 03b-consul-utils.sh
# Directory and data functions for Consul deployment

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

# Function to prepare SSL certificates for Consul
prepare_consul_ssl() {
  log "Preparing SSL certificates for Consul..."
  
  # Check if SSL for Consul is enabled in config
  if [ "${CONSUL_ENABLE_SSL:-false}" != "true" ]; then
    log "Consul SSL is not enabled in configuration. Skipping."
    return 0
  fi
  
  # Create directory for Consul certificates
  mkdir -p "${DATA_DIR}/certificates/consul" 2>/dev/null || sudo mkdir -p "${DATA_DIR}/certificates/consul"
  
  # Copy certificates from source location
  if [ -f "${PARENT_DIR}/certs/fullchain.pem" ] && [ -f "${PARENT_DIR}/certs/privkey.pem" ]; then
    cp "${PARENT_DIR}/certs/fullchain.pem" "${DATA_DIR}/certificates/consul/ca.pem" 2>/dev/null || \
    sudo cp "${PARENT_DIR}/certs/fullchain.pem" "${DATA_DIR}/certificates/consul/ca.pem"
    
    cp "${PARENT_DIR}/certs/cert.pem" "${DATA_DIR}/certificates/consul/server.pem" 2>/dev/null || \
    sudo cp "${PARENT_DIR}/certs/cert.pem" "${DATA_DIR}/certificates/consul/server.pem"
    
    cp "${PARENT_DIR}/certs/privkey.pem" "${DATA_DIR}/certificates/consul/server-key.pem" 2>/dev/null || \
    sudo cp "${PARENT_DIR}/certs/privkey.pem" "${DATA_DIR}/certificates/consul/server-key.pem"
    
    # Set appropriate permissions
    sudo chmod 644 "${DATA_DIR}/certificates/consul/ca.pem" 2>/dev/null
    sudo chmod 644 "${DATA_DIR}/certificates/consul/server.pem" 2>/dev/null
    sudo chmod 600 "${DATA_DIR}/certificates/consul/server-key.pem" 2>/dev/null
    
    success "SSL certificates prepared for Consul"
  else
    warn "SSL certificates not found at expected locations. Consul will run without SSL."
    # Set flag to disable SSL for this run
    CONSUL_ENABLE_SSL="false"
    return 1
  fi
  
  # Create TLS configuration for Consul
  mkdir -p "${CONFIG_DIR}/consul" 2>/dev/null || sudo mkdir -p "${CONFIG_DIR}/consul"
  cat > "${CONFIG_DIR}/consul/tls.json" << EOF
{
  "verify_incoming": true,
  "verify_outgoing": true,
  "verify_server_hostname": true,
  "ca_file": "/consul/config/certs/ca.pem",
  "cert_file": "/consul/config/certs/server.pem",
  "key_file": "/consul/config/certs/server-key.pem",
  "auto_encrypt": {
    "allow_tls": true
  }
}
EOF

  success "TLS configuration created for Consul"
  return 0
}

# Create Consul configuration for Nomad deployment
create_consul_job() {
  log "Creating Consul job configuration..."
  
  # Get the primary IP address if not explicitly set in config
  if [ -z "$CONSUL_BIND_ADDR" ] || [ -z "$CONSUL_ADVERTISE_ADDR" ]; then
    PRIMARY_IP=$(get_primary_ip)
    CONSUL_BIND_ADDR=${CONSUL_BIND_ADDR:-$PRIMARY_IP}
    CONSUL_ADVERTISE_ADDR=${CONSUL_ADVERTISE_ADDR:-$PRIMARY_IP}
  fi
  
  log "Using IP address: ${CONSUL_BIND_ADDR} for Consul"
  
  # Ensure job directory exists
  mkdir -p "${JOB_DIR}"
  
  # Check if SSL is enabled for Consul
  if [ "${CONSUL_ENABLE_SSL:-false}" = "true" ]; then
    log "Configuring Consul job with SSL support..."
    CONSUL_ARGS="agent -server -bootstrap -bind=${CONSUL_BIND_ADDR} -advertise=${CONSUL_ADVERTISE_ADDR} -client=0.0.0.0 -ui -config-file=/consul/config/tls.json"
    CONSUL_SSL_MOUNTS=",\n        mount {\n          type = \"bind\"\n          source = \"${CONFIG_DIR}/consul\"\n          target = \"/consul/config\"\n          readonly = true\n        },\n        mount {\n          type = \"bind\"\n          source = \"${DATA_DIR}/certificates/consul\"\n          target = \"/consul/config/certs\"\n          readonly = true\n        }"
  else
    log "Configuring Consul job without SSL support..."
    CONSUL_ARGS="\"agent\", \"-server\", \"-bootstrap\", \"-bind=${CONSUL_BIND_ADDR}\", \"-advertise=${CONSUL_ADVERTISE_ADDR}\", \"-client=0.0.0.0\", \"-ui\""
    CONSUL_SSL_MOUNTS=""
  fi
  
  # Generate Consul job file with mount directive (not using volumes array)
  cat > $JOB_DIR/consul.hcl << EOF
job "consul" {
  datacenters = ["dc1"]
  type        = "service"
  
  priority = 100
  
  group "consul" {
    count = 1
    
    network {
      mode = "host"
      
      port "http" {
        static = ${CONSUL_HTTP_PORT}
        to     = ${CONSUL_HTTP_PORT}
      }
      
      port "dns" {
        static = ${CONSUL_DNS_PORT}
        to     = ${CONSUL_DNS_PORT}
      }
      
      port "server" {
        static = 8300
        to     = 8300
      }
      
      port "serf_lan" {
        static = 8301
        to     = 8301
      }
      
      port "serf_wan" {
        static = 8302
        to     = 8302
      }
    }
    
    task "consul" {
      driver = "docker"
      
      config {
        image = "hashicorp/consul:${CONSUL_VERSION}"
        network_mode = "host"
        
        # Use mount directive for data persistence
        mount {
          type = "bind"
          source = "${DATA_DIR}/consul_data"
          target = "/consul/data"
          readonly = false
        }${CONSUL_SSL_MOUNTS}
        
        args = [
          ${CONSUL_ARGS}
        ]
      }
      
      resources {
        cpu    = ${CONSUL_CPU}
        memory = ${CONSUL_MEMORY}
      }
      
      service {
        name = "consul"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.consul.rule=Host(\`${CONSUL_HOST}\`)",
          "traefik.http.routers.consul.entrypoints=web",
          "homepage.name=Consul",
          "homepage.icon=consul.png",
          "homepage.group=Infrastructure",
          "homepage.description=Service Discovery and Mesh"
        ]
        
        check {
          type     = "http"
          path     = "/v1/status/leader"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
EOF

  # Make sure the job file is readable
  chmod 644 "${JOB_DIR}/consul.hcl"
  
  success "Consul job configuration created"
}

# Create helper scripts for managing Consul
create_helper_scripts() {
  log "Creating helper scripts for Consul management..."
  
  # Create directory for scripts
  mkdir -p "${PARENT_DIR}/bin"
  
  # Create start script with auth and SSL support
  cat > "${PARENT_DIR}/bin/start-consul.sh" << EOF
#!/bin/bash
# Helper script to start Consul with Nomad authentication and SSL

# Load Nomad token if available
if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
  source "${PARENT_DIR}/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Set Nomad SSL environment
export NOMAD_ADDR=https://127.0.0.1:4646
export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem

echo "Attempting to start Consul..."
if [ -n "\${NOMAD_TOKEN}" ]; then
  # Try with token
  nomad job run "${JOB_DIR}/consul.hcl" && echo "Consul job started successfully via CLI" && exit 0
else
  # Try without token
  nomad job run "${JOB_DIR}/consul.hcl" && echo "Consul job started successfully" && exit 0
fi

echo "Failed to start Consul job through Nomad. Check your authentication and permissions."
echo "You might need to ensure the nomad user has access to Docker:"
echo "  sudo synogroup --member docker nomad"
echo "  sudo chown root:docker /var/run/docker.sock"
exit 1
EOF
  
  # Create stop script with auth and SSL support
  cat > "${PARENT_DIR}/bin/stop-consul.sh" << EOF
#!/bin/bash
# Helper script to stop Consul with Nomad authentication and SSL

# Load Nomad token if available
if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
  source "${PARENT_DIR}/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Set Nomad SSL environment
export NOMAD_ADDR=https://127.0.0.1:4646
export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem

echo "Attempting to stop Consul..."
if [ -n "\${NOMAD_TOKEN}" ]; then
  # Try with CLI
  nomad job stop -purge consul && echo "Consul job stopped successfully via CLI" && exit 0
else
  # Try without token
  nomad job stop -purge consul && echo "Consul job stopped successfully" && exit 0
fi

echo "Failed to stop Consul job through Nomad. Check your authentication."
exit 1
EOF
  
  # Create status script with auth and SSL support
  cat > "${PARENT_DIR}/bin/consul-status.sh" << EOF
#!/bin/bash
# Helper script to check Consul status with Nomad authentication and SSL

# Load Nomad token if available
if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
  source "${PARENT_DIR}/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Set Nomad SSL environment
export NOMAD_ADDR=https://127.0.0.1:4646
export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem

echo "Checking Consul status..."

# Check status via CLI with token if available
if [ -n "\${NOMAD_TOKEN}" ]; then
  echo "Checking via Nomad CLI with token..."
  nomad job status consul
else
  # Try without token via CLI
  echo "Checking via Nomad CLI without token..."
  nomad job status consul || echo "Failed to get job status. Check your Nomad authentication."
fi

# Check Consul HTTP endpoint
echo ""
echo "Checking Consul HTTP endpoint..."
if curl -s -f "http://localhost:${CONSUL_HTTP_PORT}/v1/status/leader" &>/dev/null; then
  echo "✅ Consul HTTP endpoint is responding"
else
  echo "❌ Consul HTTP endpoint is not responding"
fi

# Check DNS endpoint
echo ""
echo "Checking Consul DNS endpoint..."
if command -v dig &>/dev/null; then
  dig @127.0.0.1 -p ${CONSUL_DNS_PORT} consul.service.consul. &>/dev/null
  if [ $? -eq 0 ]; then
    echo "✅ Consul DNS endpoint is responding"
  else
    echo "❌ Consul DNS endpoint is not responding"
  fi
else
  echo "❓ Cannot check DNS endpoint (dig command not found)"
fi

# Check ports
echo ""
echo "Checking Consul ports..."
netstat -tuln | grep "${CONSUL_HTTP_PORT}\|${CONSUL_DNS_PORT}\|8300\|8301\|8302" || echo "No Consul ports found to be listening"

# Check Docker permissions
echo ""
echo "Checking Docker permissions..."
if docker info &>/dev/null; then
  echo "✅ Docker is accessible by current user"
else
  echo "❌ Docker is not accessible by current user"
  echo "   This may cause issues if Nomad is running as a different user"
  echo "   Run these commands to fix Docker permissions:"
  echo "     sudo synogroup --member docker nomad"
  echo "     sudo chown root:docker /var/run/docker.sock"
fi

# Check SSL configuration if enabled
if [ "${CONSUL_ENABLE_SSL:-false}" = "true" ]; then
  echo ""
  echo "Checking Consul SSL configuration..."
  if [ -f "${DATA_DIR}/certificates/consul/ca.pem" ] && \
     [ -f "${DATA_DIR}/certificates/consul/server.pem" ] && \
     [ -f "${DATA_DIR}/certificates/consul/server-key.pem" ]; then
    echo "✅ Consul SSL certificates are in place"
  else
    echo "❌ Consul SSL certificates are missing"
  fi
  
  if [ -f "${CONFIG_DIR}/consul/tls.json" ]; then
    echo "✅ Consul TLS configuration exists"
  else
    echo "❌ Consul TLS configuration is missing"
  fi
fi

exit 0
EOF
  
  # Make scripts executable
  chmod +x "${PARENT_DIR}/bin/start-consul.sh"
  chmod +x "${PARENT_DIR}/bin/stop-consul.sh"
  chmod +x "${PARENT_DIR}/bin/consul-status.sh"
  
  success "Helper scripts created in ${PARENT_DIR}/bin/"
}