#!/bin/bash
# 03c-consul-utils.sh
# Deployment functions for Consul deployment

# Setup Consul DNS Integration with Synology
setup_consul_dns() {
  log "Setting up Consul DNS integration with Synology..."
  
  # Get the primary IP address if not set
  if [ -z "$CONSUL_BIND_ADDR" ]; then
    CONSUL_BIND_ADDR=$(get_primary_ip)
  fi
  
  # Add consul.service.consul to hosts file if enabled
  if [ "$DNS_USE_HOSTS_FILE" = true ]; then
    log "Adding consul.service.consul to /etc/hosts file..."
    # Check if entry already exists and remove it to avoid duplicates
    sudo sed -i '/consul\.service\.consul/d' /etc/hosts || {
      warn "Failed to remove existing hosts entry. Creating a new entry may result in duplicates."
    }
    
    # Add the new entry
    echo "${CONSUL_BIND_ADDR} consul.service.consul" | sudo tee -a /etc/hosts > /dev/null || {
      warn "Failed to add consul.service.consul to hosts file. DNS resolution may not work."
    }
    
    # Create a backup of the modified hosts file to the config directory
    sudo cp /etc/hosts ${CONFIG_DIR}/hosts.backup 2>/dev/null || {
      warn "Failed to backup hosts file to config directory."
    }
    
    log "Added hosts file entry: ${CONSUL_BIND_ADDR} consul.service.consul"
  fi
  
  # Attempt dnsmasq configuration if enabled
  if [ "$DNS_USE_DNSMASQ" = true ]; then
    log "Attempting to configure dnsmasq for Consul DNS..."
    
    # Check if dnsmasq exists
    if command -v dnsmasq &>/dev/null; then
      log "dnsmasq found, attempting to configure..."
      # Create directory for dnsmasq config if it doesn't exist
      sudo mkdir -p /etc/dnsmasq.conf.d || {
        warn "Failed to create dnsmasq config directory. Will try direct file approach."
        # Try direct file approach if directory creation fails
        echo "server=/consul/127.0.0.1#${CONSUL_DNS_PORT}" | sudo tee -a /etc/dnsmasq.conf > /dev/null || {
          warn "Failed to modify dnsmasq configuration. Using hosts file only."
        }
        cp /etc/dnsmasq.conf ${CONFIG_DIR}/dnsmasq.conf.backup 2>/dev/null || true
      }
      
      if [ -d "/etc/dnsmasq.conf.d" ]; then
        # Create or update the Consul DNS configuration
        echo "server=/consul/127.0.0.1#${CONSUL_DNS_PORT}" | sudo tee /etc/dnsmasq.conf.d/10-consul > /dev/null || {
          warn "Failed to create dnsmasq configuration file. Using hosts file only."
        }
        
        # Backup the configuration to our platform directory for restoration after DSM updates
        cp /etc/dnsmasq.conf.d/10-consul ${CONFIG_DIR}/10-consul 2>/dev/null || 
        sudo cp /etc/dnsmasq.conf.d/10-consul ${CONFIG_DIR}/10-consul 2>/dev/null || 
        warn "Failed to backup dnsmasq configuration."
      fi
      
      # Attempt to restart dnsmasq (may fail on some Synology models)
      if command -v systemctl &>/dev/null; then
        sudo systemctl restart dnsmasq 2>/dev/null || 
        warn "Failed to restart dnsmasq service. Using hosts file for DNS resolution."
      else
        warn "systemctl not found. Using hosts file for DNS resolution."
      fi
    else
      log "dnsmasq not found. Using hosts file for DNS resolution."
    fi
  fi
  
  # Test DNS resolution
  log "Testing DNS resolution for consul.service.consul..."
  if ping -c 1 consul.service.consul &>/dev/null; then
    success "Consul DNS integration configured successfully via hosts file"
  else
    warn "Consul DNS integration might not be working properly. Please check manually with: ping consul.service.consul"
  fi
  
  log "For full DNS integration throughout your network, consider adding DNS entries"
  log "in your router to forward .consul domains to ${CONSUL_BIND_ADDR}"
}

# Deploy Consul to Nomad
deploy_consul_nomad() {
  log "Deploying Consul as a Nomad job..."
  
  # Stop any existing Consul docker container from previous installations
  log "Checking for existing Consul Docker container..."
  sudo docker stop consul 2>/dev/null || true
  sudo docker rm consul 2>/dev/null || true
  
  # Stop existing Consul Nomad job if it exists
  log "Checking for existing Consul Nomad job..."
  if [ -n "${NOMAD_TOKEN}" ]; then
    NOMAD_TOKEN="${NOMAD_TOKEN}" nomad job stop -purge consul 2>/dev/null || true
  else
    nomad job stop -purge consul 2>/dev/null || true
  fi
  
  # Run the Consul job with authentication if available
  log "Starting Consul job..."
  if [ -n "${NOMAD_TOKEN}" ]; then
    NOMAD_TOKEN="${NOMAD_TOKEN}" nomad job run "${JOB_DIR}/consul.hcl"
  else
    nomad job run "${JOB_DIR}/consul.hcl"
  fi
  
  # Wait for Consul to be ready
  log "Waiting for Consul to be ready..."
  sleep 10
  
  # Check if Consul job is running
  local job_status=""
  if [ -n "${NOMAD_TOKEN}" ]; then
    job_status=$(NOMAD_TOKEN="${NOMAD_TOKEN}" nomad job status consul | grep -A 1 "Status" | tail -n 1)
  else
    job_status=$(nomad job status consul | grep -A 1 "Status" | tail -n 1)
  fi
  
  if [[ "${job_status}" == *"running"* ]]; then
    success "Consul job is running successfully in Nomad"
  else
    warn "Consul job status is not 'running'. Current status: ${job_status}"
    warn "Check Nomad UI or job logs for more details."
    
    # Get allocation logs if possible
    log "Checking allocation logs..."
    local ALLOC_ID=""
    if [ -n "${NOMAD_TOKEN}" ]; then
      ALLOC_ID=$(NOMAD_TOKEN="${NOMAD_TOKEN}" nomad job status -json consul 2>/dev/null | grep -o '"ID":"[^"]*"' | head -1 | cut -d '"' -f 4)
    else
      ALLOC_ID=$(nomad job status -json consul 2>/dev/null | grep -o '"ID":"[^"]*"' | head -1 | cut -d '"' -f 4)
    fi
    
    if [ -n "$ALLOC_ID" ]; then
      if [ -n "${NOMAD_TOKEN}" ]; then
        NOMAD_TOKEN="${NOMAD_TOKEN}" nomad alloc logs $ALLOC_ID 2>/dev/null || true
      else
        nomad alloc logs $ALLOC_ID 2>/dev/null || true
      fi
    fi
  fi
  
  # Check if Consul service is responding
  if ! curl -s http://localhost:${CONSUL_HTTP_PORT}/v1/status/leader > /dev/null; then
    warn "Consul service might not be fully operational yet."
    warn "Please check if the service is running using: curl -v http://localhost:${CONSUL_HTTP_PORT}/v1/status/leader"
  else
    success "Consul is running and responding to requests"
  fi
  
  # Create a reference file
  cat > $JOB_DIR/consul.reference << EOF
# Consul deployed as a Nomad job
# To restart: ${PARENT_DIR}/bin/start-consul.sh
# To stop: ${PARENT_DIR}/bin/stop-consul.sh
# To view status: ${PARENT_DIR}/bin/consul-status.sh 
# To view logs: nomad alloc logs <allocation-id>
# IP address: ${CONSUL_BIND_ADDR}
# SSL enabled: ${CONSUL_ENABLE_SSL:-false}
EOF

  success "Consul deployment completed"
}

# Deploy Consul using direct Docker command (legacy method)
deploy_consul_docker() {
  log "Deploying Consul using direct Docker command for Synology..."
  
  # Get the primary IP address if not explicitly set in config
  if [ -z "$CONSUL_BIND_ADDR" ] || [ -z "$CONSUL_ADVERTISE_ADDR" ]; then
    PRIMARY_IP=$(get_primary_ip)
    CONSUL_BIND_ADDR=${CONSUL_BIND_ADDR:-$PRIMARY_IP}
    CONSUL_ADVERTISE_ADDR=${CONSUL_ADVERTISE_ADDR:-$PRIMARY_IP}
  fi
  
  log "Using IP address: ${CONSUL_BIND_ADDR} for Consul"
  
  # Check if Docker is available
  if ! command -v docker &>/dev/null; then
    error "Docker is not available. Please install Docker first."
  fi
  
  # Stop and remove any existing Consul container
  log "Stopping any existing Consul container..."
  sudo docker stop consul 2>/dev/null || true
  sudo docker rm consul 2>/dev/null || true
  
  # Configure SSL if enabled
  local ssl_volumes=""
  local ssl_args=""
  if [ "${CONSUL_ENABLE_SSL:-false}" = "true" ]; then
    log "Configuring Consul Docker with SSL support..."
    ssl_volumes="-v ${CONFIG_DIR}/consul:/consul/config -v ${DATA_DIR}/certificates/consul:/consul/config/certs"
    ssl_args="-config-file=/consul/config/tls.json"
  fi
  
  # Create startup script for Consul
  log "Creating startup script for Consul..."
  
  mkdir -p ${PARENT_DIR}/bin
  cat > ${PARENT_DIR}/bin/start-consul.sh << EOF
#!/bin/bash
# Start Consul container

# Get the primary IP if not passed
if [ -z "\$PRIMARY_IP" ]; then
  PRIMARY_IP=\$(ip route get 1 | awk '{print \$7;exit}' 2>/dev/null || hostname -I | awk '{print \$1}')
  if [ -z "\$PRIMARY_IP" ]; then
    echo "Error: Could not determine primary IP address"
    exit 1
  fi
fi

sudo docker stop consul 2>/dev/null || true
sudo docker rm consul 2>/dev/null || true
sudo docker run -d --name consul \\
  --restart always \\
  --network host \\
  -v ${DATA_DIR}/consul_data:/consul/data \\
  ${ssl_volumes} \\
  hashicorp/consul:${CONSUL_VERSION} \\
  agent -server -bootstrap \\
  -bind=${CONSUL_BIND_ADDR} \\
  -advertise=${CONSUL_ADVERTISE_ADDR} \\
  -client=0.0.0.0 \\
  -ui \\
  ${ssl_args}
EOF
  
  chmod +x ${PARENT_DIR}/bin/start-consul.sh
  
  # Create stop script for Consul
  cat > ${PARENT_DIR}/bin/stop-consul.sh << EOF
#!/bin/bash
# Stop Consul container
sudo docker stop consul
sudo docker rm consul
EOF
  
  chmod +x ${PARENT_DIR}/bin/stop-consul.sh
  
  # Run the start script
  log "Starting Consul container..."
  PRIMARY_IP="${CONSUL_BIND_ADDR}" ${PARENT_DIR}/bin/start-consul.sh
  
  # Wait for Consul to be ready
  log "Waiting for Consul to be ready..."
  sleep 10
  
  # Check if Consul is running
  if ! curl -s http://localhost:${CONSUL_HTTP_PORT}/v1/status/leader > /dev/null; then
    warn "Consul might not be fully operational yet. Please check status manually with: sudo docker logs consul"
    if ! sudo docker ps | grep -q "consul.*Up"; then
      log "Consul container is not running. Checking logs:"
      sudo docker logs consul
      warn "Please fix the issues and restart the container manually with: sudo ${PARENT_DIR}/bin/start-consul.sh"
    fi
  else
    success "Consul is running and responding to requests"
  fi

  # Create a nomad job reference file for uninstall purposes
  mkdir -p $JOB_DIR
  cat > $JOB_DIR/consul.reference << EOF
# Note: Consul was deployed directly as a Docker container
# To restart: ${PARENT_DIR}/bin/start-consul.sh
# To stop: ${PARENT_DIR}/bin/stop-consul.sh
# To view logs: sudo docker logs consul
# Container name: consul
# IP address: ${CONSUL_BIND_ADDR}
# SSL enabled: ${CONSUL_ENABLE_SSL:-false}
EOF

  success "Consul deployment completed"
}