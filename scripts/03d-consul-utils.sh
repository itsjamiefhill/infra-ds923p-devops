#!/bin/bash
# 03d-consul-utils.sh
# Helper functions for Consul Docker deployment

# Display usage information
usage() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --help    Show this help message"
  echo "  --force   Force operation without prompts"
}

# Function to display access information
show_access_info() {
  # Use directly from config without fallbacks
  SYNOLOGY_IP=$(get_primary_ip)
  
  echo -e "\n${GREEN}==========================================================${NC}"
  echo -e "${GREEN}                Consul Deployment Complete               ${NC}"
  echo -e "${GREEN}==========================================================${NC}"
  echo -e "\n${BLUE}Consul is now available at:${NC}\n"
  
  if [ "${CONSUL_ENABLE_SSL}" = "true" ]; then
    echo -e "  * UI: ${YELLOW}https://${CONSUL_HOST}:${CONSUL_HTTP_PORT}${NC} or ${YELLOW}https://${SYNOLOGY_IP}:${CONSUL_HTTP_PORT}${NC}"
    echo -e "  * API: ${YELLOW}https://${SYNOLOGY_IP}:${CONSUL_HTTP_PORT}/v1/${NC}"
  else
    echo -e "  * UI: ${YELLOW}http://${CONSUL_HOST}${NC} or ${YELLOW}http://${SYNOLOGY_IP}:${CONSUL_HTTP_PORT}${NC}"
    echo -e "  * API: ${YELLOW}http://${SYNOLOGY_IP}:${CONSUL_HTTP_PORT}/v1/${NC}"
  fi
  
  echo -e "  * DNS: ${YELLOW}${SYNOLOGY_IP}:${CONSUL_DNS_PORT}${NC} (for .consul domains)"
  
  # Show SSL information if enabled
  if [ "${CONSUL_ENABLE_SSL}" = "true" ]; then
    echo -e "\n${BLUE}SSL Configuration:${NC}"
    echo -e "  * Consul SSL: ${YELLOW}Enabled${NC}"
    echo -e "  * Certificate location: ${YELLOW}${DATA_DIR}/certificates/consul${NC}"
    echo -e "  * Config location: ${YELLOW}${CONFIG_DIR}/consul${NC}"
    echo -e "  * Note: The UI is configured to use HTTPS only. HTTP is disabled."
    echo -e "  * Note: You will see certificate warnings in your browser (this is normal for self-signed certs)"
  fi
  
  # Show ACL information if enabled - with robust error handling
  if [ "${CONSUL_ENABLE_ACL}" = "true" ]; then
    echo -e "\n${BLUE}ACL Configuration:${NC}"
    echo -e "  * Consul ACL: ${YELLOW}Enabled${NC}"
    echo -e "  * Default policy: ${YELLOW}deny${NC} (explicitly allow access)"
    
    if [ -f "${PARENT_DIR}/secrets/consul_tokens.json" ]; then
      # Check if file is readable before trying to parse it
      if [ -r "${PARENT_DIR}/secrets/consul_tokens.json" ]; then
        # First check if jq is available
        if command -v jq &> /dev/null; then
          # Safely get the bootstrap token with default value if missing
          local BS_TOKEN
          BS_TOKEN=$(jq -r '.bootstrap_token // "Not available"' "${PARENT_DIR}/secrets/consul_tokens.json" 2>/dev/null || echo "Error reading token")
          
          if [ "$BS_TOKEN" != "Error reading token" ]; then
            echo -e "  * Bootstrap Token: ${YELLOW}${BS_TOKEN}${NC}"
          else
            echo -e "  * Bootstrap Token: ${YELLOW}Available but could not be read${NC}"
          fi
        else
          echo -e "  * Bootstrap Token: ${YELLOW}Available but jq not installed to read it${NC}"
        fi
        echo -e "  * Tokens file: ${YELLOW}${PARENT_DIR}/secrets/consul_tokens.json${NC}"
        echo -e "  * Token helper: ${YELLOW}${PARENT_DIR}/bin/consul-tokens.sh${NC}"
      else
        echo -e "  * ACL Tokens: ${YELLOW}File exists but is not readable${NC}"
      fi
    else
      echo -e "  * ACL Tokens: ${YELLOW}Not yet generated${NC}"
    fi
  fi
  
  echo -e "\n${BLUE}Management Scripts:${NC}"
  echo -e "  * Start Consul: ${YELLOW}${PARENT_DIR}/bin/start-consul.sh${NC}"
  echo -e "  * Stop Consul: ${YELLOW}${PARENT_DIR}/bin/stop-consul.sh${NC}"
  echo -e "  * Check Status: ${YELLOW}${PARENT_DIR}/bin/consul-status.sh${NC}"
  echo -e "  * View Logs: ${YELLOW}${PARENT_DIR}/bin/consul-logs.sh${NC}"
  echo -e "  * Troubleshooting: ${YELLOW}${PARENT_DIR}/bin/consul-troubleshoot.sh${NC}"
  
  echo -e "\n${BLUE}Data Directory:${NC}"
  echo -e "  * Location: ${YELLOW}${DATA_DIR}/consul_data${NC}"
  echo -e "  * Mounted at: ${YELLOW}/consul/data${NC} in the container"
  
  echo -e "\n${BLUE}Docker Configuration:${NC}"
  echo -e "  * Container Name: ${YELLOW}consul${NC}"
  echo -e "  * Image: ${YELLOW}hashicorp/consul:${CONSUL_VERSION}${NC}"
  echo -e "  * Network Mode: ${YELLOW}host${NC}"
  echo -e "  * Restart Policy: ${YELLOW}always${NC}"
  
  echo -e "\n${BLUE}Troubleshooting:${NC}"
  echo -e "  * View container status: ${YELLOW}sudo docker ps | grep consul${NC}"
  echo -e "  * View container logs: ${YELLOW}sudo docker logs consul${NC} or ${YELLOW}${PARENT_DIR}/bin/consul-logs.sh${NC}"
  echo -e "  * Restart container: ${YELLOW}${PARENT_DIR}/bin/stop-consul.sh && ${PARENT_DIR}/bin/start-consul.sh${NC}"
  echo -e "  * Full troubleshooting: ${YELLOW}${PARENT_DIR}/bin/consul-troubleshoot.sh${NC}"
  
  echo -e "\n${GREEN}==========================================================${NC}"
}

# Function to update start script for ACL
update_start_script_for_acl() {
  log "Updating start-consul.sh script to include ACL configuration..."
  
  # Create a temporary file for the new script content
  local TEMP_START_SCRIPT=$(mktemp)
  
  # Build the script content based on the configured features
  cat > "$TEMP_START_SCRIPT" << EOF
#!/bin/bash
# Helper script to start Consul with Docker

# Get the primary IP if not passed
if [ -z "\$PRIMARY_IP" ]; then
  # Try to determine the primary IP address
  PRIMARY_IP=\$(ip route get 1 | awk '{print \$7;exit}' 2>/dev/null)
  
  # If that doesn't work, try an alternative method
  if [ -z "\$PRIMARY_IP" ]; then
    PRIMARY_IP=\$(hostname -I | awk '{print \$1}')
  fi
  
  if [ -z "\$PRIMARY_IP" ]; then
    echo "Error: Could not determine IP address"
    exit 1
  fi
fi

# Stop any existing container
echo "Stopping any existing Consul container..."
sudo docker stop consul 2>/dev/null || true
sudo docker rm consul 2>/dev/null || true

# Ensure the config directory has the correct permissions for the container
if [ -d "${CONFIG_DIR}/consul" ]; then
  echo "Setting appropriate permissions on Consul config directory..."
  sudo chmod -R 755 "${CONFIG_DIR}/consul"
  sudo chmod 644 ${CONFIG_DIR}/consul/*.json 2>/dev/null || true
  
  # Try to set proper ownership for the Consul container user (UID 100)
  if command -v id &>/dev/null && sudo -n true 2>/dev/null; then
    sudo chown -R 100:100 "${CONFIG_DIR}/consul" 2>/dev/null || true
  fi
fi

EOF

  # Add Docker run command with appropriate configurations
  if [ "${CONSUL_ENABLE_SSL}" = "true" ] && [ "${CONSUL_ENABLE_ACL}" = "true" ]; then
    # Both SSL and ACL enabled
    cat >> "$TEMP_START_SCRIPT" << EOF
# Starting Consul container with SSL and ACL enabled
echo "Starting Consul container with SSL and ACL..."
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
  -config-file=/consul/config/tls.json \\
  -config-file=/consul/config/acl.json

EOF
  elif [ "${CONSUL_ENABLE_SSL}" = "true" ]; then
    # Only SSL enabled
    cat >> "$TEMP_START_SCRIPT" << EOF
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
  elif [ "${CONSUL_ENABLE_ACL}" = "true" ]; then
    # Only ACL enabled
    cat >> "$TEMP_START_SCRIPT" << EOF
# Starting Consul container with ACL enabled
echo "Starting Consul container with ACL..."
sudo docker run -d \\
  --name consul \\
  --restart always \\
  --network host \\
  -v "${DATA_DIR}/consul_data:/consul/data" \\
  -v "${CONFIG_DIR}/consul:/consul/config" \\
  hashicorp/consul:${CONSUL_VERSION} \\
  agent -server -bootstrap \\
  -bind=\$PRIMARY_IP \\
  -advertise=\$PRIMARY_IP \\
  -client=0.0.0.0 \\
  -datacenter=${CONSUL_DATACENTER:-dc1} \\
  -ui \\
  -config-file=/consul/config/acl.json

EOF
  else
    # Neither SSL nor ACL enabled
    cat >> "$TEMP_START_SCRIPT" << EOF
# Starting Consul container without SSL or ACL
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

  # Add final check and status
  cat >> "$TEMP_START_SCRIPT" << EOF
# Check if container started successfully
if [ \$? -eq 0 ]; then
  echo "Consul container started successfully"
  echo "UI available at http://\$PRIMARY_IP:${CONSUL_HTTP_PORT}"
  echo "Datacenter: ${CONSUL_DATACENTER:-dc1}"
  echo "ACL enabled: ${CONSUL_ENABLE_ACL:-false}"
  echo "SSL enabled: ${CONSUL_ENABLE_SSL:-false}"
  exit 0
else
  echo "Failed to start Consul container"
  exit 1
fi
EOF

  # Copy the temporary script to the destination and make it executable
  mkdir -p "${PARENT_DIR}/bin"
  cp "$TEMP_START_SCRIPT" "${PARENT_DIR}/bin/start-consul.sh"
  chmod +x "${PARENT_DIR}/bin/start-consul.sh"
  
  # Clean up the temporary file
  rm "$TEMP_START_SCRIPT"
  
  log "Updated start-consul.sh script with ACL support"
}