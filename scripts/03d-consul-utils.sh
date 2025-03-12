#!/bin/bash
# 03d-consul-utils.sh
# Helper functions for Consul deployment

# Function to display access information
show_access_info() {
  CONSUL_HOST=${CONSUL_HOST:-"consul.${DOMAIN:-homelab.local}"}
  SYNOLOGY_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
  
  echo -e "\n${GREEN}==========================================================${NC}"
  echo -e "${GREEN}                Consul Deployment Complete               ${NC}"
  echo -e "${GREEN}==========================================================${NC}"
  echo -e "\n${BLUE}Consul is now available at:${NC}\n"
  echo -e "  * UI: ${YELLOW}http://${CONSUL_HOST}${NC} or ${YELLOW}http://${SYNOLOGY_IP}:${CONSUL_HTTP_PORT}${NC}"
  echo -e "  * API: ${YELLOW}http://${SYNOLOGY_IP}:${CONSUL_HTTP_PORT}/v1/${NC}"
  echo -e "  * DNS: ${YELLOW}${SYNOLOGY_IP}:${CONSUL_DNS_PORT}${NC} (for .consul domains)"
  
  echo -e "\n${BLUE}Management Scripts:${NC}"
  echo -e "  * Start Consul: ${YELLOW}${PARENT_DIR}/bin/start-consul.sh${NC}"
  echo -e "  * Stop Consul: ${YELLOW}${PARENT_DIR}/bin/stop-consul.sh${NC}"
  echo -e "  * Check Status: ${YELLOW}${PARENT_DIR}/bin/consul-status.sh${NC}"
  
  echo -e "\n${BLUE}Data Directory:${NC}"
  echo -e "  * Location: ${YELLOW}${DATA_DIR}/consul_data${NC}"
  echo -e "  * Mounted at: ${YELLOW}/consul/data${NC} in the container"
  
  echo -e "\n${BLUE}Troubleshooting:${NC}"
  echo -e "  * If you encounter 'missing drivers' error, ensure Docker permissions are correct:"
  echo -e "    - ${YELLOW}sudo synogroup --add docker${NC} # create docker group if needed"
  echo -e "    - ${YELLOW}sudo synogroup --member docker nomad${NC} # add nomad user to docker group"
  echo -e "    - ${YELLOW}sudo chown root:docker /var/run/docker.sock${NC} # fix socket permissions"
  echo -e "    - Restart Nomad after making these changes"
  
  echo -e "\n${GREEN}==========================================================${NC}"
}

# Create a Docker fallback deployment script if Nomad fails
create_docker_fallback() {
  log "Creating Docker fallback deployment script..."
  
  mkdir -p "${PARENT_DIR}/bin"
  
  # Create the Docker run script
  cat > "${PARENT_DIR}/bin/consul-docker-run.sh" << EOF
#!/bin/bash
# Direct Docker deployment for Consul
# Created as a fallback due to Nomad Docker driver issues

# Stop any existing container
docker stop consul 2>/dev/null || true
docker rm consul 2>/dev/null || true

# Get the primary IP if not passed
if [ -z "\$PRIMARY_IP" ]; then
  PRIMARY_IP=\$(ip route get 1 | awk '{print \$7;exit}' 2>/dev/null || hostname -I | awk '{print \$1}')
  if [ -z "\$PRIMARY_IP" ]; then
    echo "Error: Could not determine primary IP address"
    exit 1
  fi
fi

echo "Starting Consul container with Docker..."
docker run -d \\
  --name consul \\
  --restart unless-stopped \\
  --network host \\
  -v "${DATA_DIR}/consul_data:/consul/data" \\
  hashicorp/consul:${CONSUL_VERSION} \\
  agent -server -bootstrap \\
  -bind=\$PRIMARY_IP \\
  -advertise=\$PRIMARY_IP \\
  -client=0.0.0.0 \\
  -ui

echo "Consul started with Docker. UI available at http://localhost:${CONSUL_HTTP_PORT}"
EOF

  chmod +x "${PARENT_DIR}/bin/consul-docker-run.sh"
  
  # Create stop script
  cat > "${PARENT_DIR}/bin/consul-docker-stop.sh" << EOF
#!/bin/bash
# Stop the Consul container started with Docker

echo "Stopping Consul container..."
docker stop consul
docker rm consul
echo "Consul container stopped and removed."
EOF

  chmod +x "${PARENT_DIR}/bin/consul-docker-stop.sh"
  
  # Create quick troubleshooting script
  cat > "${PARENT_DIR}/bin/consul-troubleshoot.sh" << EOF
#!/bin/bash
# Quick troubleshooting script for Consul

echo "=== Consul Troubleshooting ==="
echo "Checking Consul status..."

# Check if Consul is running in Docker
if docker ps | grep -q consul; then
  echo "✅ Consul is running as a Docker container"
  echo ""
  echo "Container details:"
  docker ps | grep consul
  echo ""
  echo "Container logs:"
  docker logs --tail 20 consul
else
  echo "❌ Consul is not running as a Docker container"
fi

# Check if Consul is running as a Nomad job
if command -v nomad &>/dev/null; then
  echo ""
  echo "Checking Nomad job status..."
  
  # Load Nomad token if available
  if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
    source "${PARENT_DIR}/config/nomad_auth.conf"
  fi
  
  if [ -n "\${NOMAD_TOKEN}" ]; then
    NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job status consul || echo "No Consul job found in Nomad"
  else
    nomad job status consul || echo "No Consul job found in Nomad"
  fi
fi

# Check if Consul API is responding
echo ""
echo "Checking Consul API..."
if curl -s -f "http://localhost:${CONSUL_HTTP_PORT}/v1/status/leader" &>/dev/null; then
  echo "✅ Consul API is responding at http://localhost:${CONSUL_HTTP_PORT}"
  echo "Leader: \$(curl -s http://localhost:${CONSUL_HTTP_PORT}/v1/status/leader)"
else
  echo "❌ Consul API is not responding at http://localhost:${CONSUL_HTTP_PORT}"
fi

# Check ports
echo ""
echo "Checking for open ports..."
netstat -tuln | grep "${CONSUL_HTTP_PORT}\|${CONSUL_DNS_PORT}" || echo "No Consul ports found"

# Check DNS resolution
echo ""
echo "Checking DNS resolution..."
ping -c 1 consul.service.consul &>/dev/null && echo "✅ consul.service.consul resolves correctly" || echo "❌ consul.service.consul does not resolve"

echo ""
echo "=== End of Troubleshooting ==="
EOF

  chmod +x "${PARENT_DIR}/bin/consul-troubleshoot.sh"
  
  log "Created Docker fallback scripts in ${PARENT_DIR}/bin/"
}