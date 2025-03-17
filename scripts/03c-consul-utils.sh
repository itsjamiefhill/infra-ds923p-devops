#!/bin/bash
# 03c-consul-utils.sh
# DNS integration and helper functions for Consul Docker deployment

# Create Docker-specific helper scripts
create_docker_helper_scripts() {
  log "Creating Docker helper scripts for Consul management..."
  
  # Create directory for scripts
  mkdir -p "${PARENT_DIR}/bin"
  
  # Create consul-docker-run.sh (start script)
  cat > "${PARENT_DIR}/bin/start-consul.sh" << EOF
#!/bin/bash
# Helper script to start Consul with Docker

# Get the primary IP if not passed
if [ -z "\$PRIMARY_IP" ]; then
  PRIMARY_IP=\$(get_primary_ip)
fi

# Stop any existing container
echo "Stopping any existing Consul container..."
sudo docker stop consul 2>/dev/null || true
sudo docker rm consul 2>/dev/null || true

EOF

  # Add SSL volumes if enabled
  if [ "${CONSUL_ENABLE_SSL:-false}" = "true" ]; then
    cat >> "${PARENT_DIR}/bin/start-consul.sh" << EOF
# Starting Consul container with SSL enabled
echo "Starting Consul container with SSL..."
sudo docker run -d \\
  --name consul \\
  --restart always \\
  --network host \\
  -v "${DATA_DIR}/consul_data:/consul/data" \\
  -v "${CONFIG_DIR}/consul:/consul/config" \\
  -v "${DATA_DIR}/certificates/consul:/consul/config/certs" \\
  hashicorp/consul:${CONSUL_VERSION} \\
  agent -server -bootstrap \\
  -bind=\$PRIMARY_IP \\
  -advertise=\$PRIMARY_IP \\
  -client=0.0.0.0 \\
  -datacenter=${CONSUL_DATACENTER:-dc1} \\
  -ui \\
  -config-file=/consul/config/tls.json

EOF
  else
    cat >> "${PARENT_DIR}/bin/start-consul.sh" << EOF
# Starting Consul container without SSL
echo "Starting Consul container..."
sudo docker run -d \\
  --name consul \\
  --restart always \\
  --network host \\
  -v "${DATA_DIR}/consul_data:/consul/data" \\
  hashicorp/consul:${CONSUL_VERSION} \\
  agent -server -bootstrap \\
  -bind=\$PRIMARY_IP \\
  -advertise=\$PRIMARY_IP \\
  -client=0.0.0.0 \\
  -datacenter=${CONSUL_DATACENTER:-dc1} \\
  -ui

EOF
  fi

  cat >> "${PARENT_DIR}/bin/start-consul.sh" << EOF
# Check if container started successfully
if [ \$? -eq 0 ]; then
  echo "Consul container started successfully"
  echo "UI available at http://\$PRIMARY_IP:${CONSUL_HTTP_PORT}"
  echo "Datacenter: ${CONSUL_DATACENTER:-dc1}"
  exit 0
else
  echo "Failed to start Consul container"
  exit 1
fi
EOF

  # Create stop script
  cat > "${PARENT_DIR}/bin/stop-consul.sh" << EOF
#!/bin/bash
# Helper script to stop Consul container

echo "Stopping Consul container..."
sudo docker stop consul
if [ \$? -eq 0 ]; then
  sudo docker rm consul
  echo "Consul container stopped and removed"
  exit 0
else
  echo "Failed to stop Consul container or container not running"
  exit 1
fi
EOF

  # Create status script
  cat > "${PARENT_DIR}/bin/consul-status.sh" << EOF
#!/bin/bash
# Helper script to check Consul status

echo "Checking Consul container status..."
if sudo docker ps | grep -q "consul"; then
  echo "✅ Consul container is running"
  echo ""
  echo "Container details:"
  sudo docker ps --filter "name=consul" --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
else
  echo "❌ Consul container is not running"
  
  # Check if it exists but is stopped
  if sudo docker ps -a | grep -q "consul"; then
    echo "Consul container exists but is not running"
    echo ""
    echo "Container details:"
    sudo docker ps -a --filter "name=consul" --format "table {{.ID}}\t{{.Image}}\t{{.Status}}"
  fi
fi

# Check Consul HTTP endpoint
echo ""
echo "Checking Consul HTTP endpoint..."
if curl -s -f "http://localhost:${CONSUL_HTTP_PORT}/v1/status/leader" &>/dev/null; then
  echo "✅ Consul HTTP endpoint is responding"
  echo "Leader: \$(curl -s http://localhost:${CONSUL_HTTP_PORT}/v1/status/leader)"
  
  # Get datacenter information
  echo "Datacenter: \$(curl -s http://localhost:${CONSUL_HTTP_PORT}/v1/agent/self | grep -o '\"Datacenter\":\"[^\"]*\"' | cut -d':' -f2 | tr -d '\"')"
else
  echo "❌ Consul HTTP endpoint is not responding"
fi

# Check DNS endpoint
echo ""
echo "Checking Consul DNS endpoint..."
if command -v dig &>/dev/null; then
  dig @127.0.0.1 -p ${CONSUL_DNS_PORT} consul.service.consul. &>/dev/null
  if [ \$? -eq 0 ]; then
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

# Check SSL configuration if enabled
if [ "${CONSUL_ENABLE_SSL:-false}" = "true" ]; then
  echo ""
  echo "Checking Consul SSL configuration..."
  if [ -f "${DATA_DIR}/certificates/consul/ca.pem" ] && \\
     [ -f "${DATA_DIR}/certificates/consul/server.pem" ] && \\
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

# Check hosts file
echo ""
echo "Checking hosts file configuration..."
if grep -q "consul\.service\.consul" /etc/hosts; then
  echo "✅ consul.service.consul entry found in /etc/hosts"
else
  echo "❌ consul.service.consul entry not found in /etc/hosts"
fi

if grep -q "${CONSUL_HOST}" /etc/hosts; then
  echo "✅ ${CONSUL_HOST} entry found in /etc/hosts"
else
  echo "❌ ${CONSUL_HOST} entry not found in /etc/hosts"
fi

exit 0
EOF

  # Create logs script for convenience
  cat > "${PARENT_DIR}/bin/consul-logs.sh" << EOF
#!/bin/bash
# Helper script to view Consul logs

if [ "\$1" == "--help" ] || [ "\$1" == "-h" ]; then
  echo "Usage: \$0 [--follow|-f] [--tail=<N>]"
  echo ""
  echo "Options:"
  echo "  --follow, -f    Follow log output"
  echo "  --tail=<N>      Show last N lines of logs (default: all)"
  exit 0
fi

FOLLOW=""
TAIL=""

# Parse arguments
for arg in "\$@"; do
  case \$arg in
    --follow|-f)
      FOLLOW="--follow"
      ;;
    --tail=*)
      TAIL="--tail=\${arg#*=}"
      ;;
  esac
done

# Check if Consul container is running
if ! sudo docker ps | grep -q "consul"; then
  echo "❌ Consul container is not running!"
  
  # Check if it exists but is stopped
  if sudo docker ps -a | grep -q "consul"; then
    echo "Consul container exists but is not running"
    echo "Use 'start-consul.sh' to start it"
  else
    echo "Consul container does not exist"
    echo "Use 'start-consul.sh' to create and start it"
  fi
  
  exit 1
fi

# View logs
echo "Displaying Consul logs..."
echo "----------------------------------------------------------------"
sudo docker logs \$FOLLOW \$TAIL consul
EOF
  
  # Create troubleshooting script
  cat > "${PARENT_DIR}/bin/consul-troubleshoot.sh" << EOF
#!/bin/bash
# Quick troubleshooting script for Consul

echo "=== Consul Troubleshooting ==="
echo "Checking Consul status..."

# Check if Consul is running in Docker
if sudo docker ps | grep -q consul; then
  echo "✅ Consul is running as a Docker container"
  echo ""
  echo "Container details:"
  sudo docker ps --filter "name=consul" --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
  echo ""
  echo "Container logs (last 20 lines):"
  sudo docker logs --tail 20 consul
else
  echo "❌ Consul is not running as a Docker container"
  
  # Check if it exists but is stopped
  if sudo docker ps -a | grep -q consul; then
    echo "Consul container exists but is not running"
    echo "Last logs before it stopped:"
    sudo docker logs --tail 20 consul
  fi
fi

# Check if Consul API is responding
echo ""
echo "Checking Consul API..."
if curl -s -f "http://localhost:${CONSUL_HTTP_PORT}/v1/status/leader" &>/dev/null; then
  echo "✅ Consul API is responding at http://localhost:${CONSUL_HTTP_PORT}"
  echo "Leader: \$(curl -s http://localhost:${CONSUL_HTTP_PORT}/v1/status/leader)"
  echo "Datacenter: \$(curl -s http://localhost:${CONSUL_HTTP_PORT}/v1/agent/self | grep -o '\"Datacenter\":\"[^\"]*\"' | cut -d':' -f2 | tr -d '\"')"
else
  echo "❌ Consul API is not responding at http://localhost:${CONSUL_HTTP_PORT}"
  
  # Try to identify why it's not responding
  if sudo docker ps | grep -q consul; then
    echo ""
    echo "Container is running but API is not responding. Possible issues:"
    echo "1. Network configuration problem"
    echo "2. Consul not fully started or failing to bootstrap"
    echo "3. SSL misconfiguration (if SSL is enabled)"
    echo ""
    echo "Full logs may contain more information:"
    echo "sudo docker logs consul"
  fi
fi

# Check ports
echo ""
echo "Checking for open ports..."
netstat -tuln | grep "${CONSUL_HTTP_PORT}\|${CONSUL_DNS_PORT}\|8300\|8301\|8302" || echo "No Consul ports found"

# Check DNS resolution
echo ""
echo "Checking DNS resolution..."
ping -c 1 ${CONSUL_HOST} &>/dev/null && echo "✅ ${CONSUL_HOST} resolves correctly" || echo "❌ ${CONSUL_HOST} does not resolve"
ping -c 1 consul.service.consul &>/dev/null && echo "✅ consul.service.consul resolves correctly" || echo "❌ consul.service.consul does not resolve"

# Check DNS for datacenter-specific services
ping -c 1 consul.service.${CONSUL_DATACENTER:-dc1}.consul &>/dev/null && echo "✅ consul.service.${CONSUL_DATACENTER:-dc1}.consul resolves correctly" || echo "❌ consul.service.${CONSUL_DATACENTER:-dc1}.consul does not resolve"

# Check SSL configuration if enabled
if [ "${CONSUL_ENABLE_SSL:-false}" = "true" ]; then
  echo ""
  echo "Checking Consul SSL configuration..."
  if [ -f "${DATA_DIR}/certificates/consul/ca.pem" ] && \\
     [ -f "${DATA_DIR}/certificates/consul/server.pem" ] && \\
     [ -f "${DATA_DIR}/certificates/consul/server-key.pem" ]; then
    echo "✅ SSL certificates exist at ${DATA_DIR}/certificates/consul/"
  else
    echo "❌ SSL certificates are missing from ${DATA_DIR}/certificates/consul/"
  fi
  
  if [ -f "${CONFIG_DIR}/consul/tls.json" ]; then
    echo "✅ TLS configuration exists at ${CONFIG_DIR}/consul/tls.json"
    echo "Configuration contents:"
    cat "${CONFIG_DIR}/consul/tls.json"
  else
    echo "❌ TLS configuration file is missing"
  fi
fi

# Check volume permissions
echo ""
echo "Checking volume permissions..."
ls -la "${DATA_DIR}/consul_data" || echo "❌ Consul data directory doesn't exist or is not accessible"

# Check image
echo ""
echo "Checking Consul image..."
sudo docker images | grep consul || echo "❌ No Consul image found"

echo ""
echo "=== End of Troubleshooting ==="
echo ""
echo "If issues persist, try the following:"
echo "1. Run 'stop-consul.sh' to stop the current container"
echo "2. Run 'start-consul.sh' to start a fresh container"
echo "3. Check logs with 'consul-logs.sh'"
echo "4. If SSL is enabled, verify certificate paths and permissions"
EOF

  # Make all scripts executable
  chmod +x "${PARENT_DIR}/bin/start-consul.sh"
  chmod +x "${PARENT_DIR}/bin/stop-consul.sh"
  chmod +x "${PARENT_DIR}/bin/consul-status.sh"
  chmod +x "${PARENT_DIR}/bin/consul-logs.sh"
  chmod +x "${PARENT_DIR}/bin/consul-troubleshoot.sh"
  
  success "Docker-specific helper scripts created in ${PARENT_DIR}/bin/"
}

# Setup Consul DNS Integration with Synology
setup_consul_dns() {
  log "Setting up Consul DNS integration with Synology..."
  
  # Get the primary IP address using standardized function
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
    
    # Add datacenter-specific entry
    echo "${CONSUL_BIND_ADDR} consul.service.${CONSUL_DATACENTER:-dc1}.consul" | sudo tee -a /etc/hosts > /dev/null || {
      warn "Failed to add datacenter-specific consul entry to hosts file."
    }
    
    # Create a backup of the modified hosts file to the config directory
    sudo cp /etc/hosts ${CONFIG_DIR}/hosts.backup 2>/dev/null || {
      warn "Failed to backup hosts file to config directory."
    }
    
    log "Added hosts file entries for Consul DNS integration"
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
  
  # Test datacenter-specific DNS resolution
  log "Testing DNS resolution for datacenter-specific consul service..."
  if ping -c 1 consul.service.${CONSUL_DATACENTER:-dc1}.consul &>/dev/null; then
    success "Datacenter-specific Consul DNS integration configured successfully"
  else
    warn "Datacenter-specific Consul DNS integration might not be working properly"
  fi
  
  log "For full DNS integration throughout your network, consider adding DNS entries"
  log "in your router to forward .consul domains to ${CONSUL_BIND_ADDR}"
}