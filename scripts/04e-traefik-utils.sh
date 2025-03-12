#!/bin/bash
# 04e-traefik-utils.sh
# Helper script functions for Traefik deployment

# Function to create helper scripts
create_helper_scripts() {
  log "Creating helper scripts for Traefik management..."
  
  # Create directory for scripts
  mkdir -p "${PARENT_DIR}/bin"
  
  # Create start script with auth
  cat > "${PARENT_DIR}/bin/start-traefik.sh" << EOF
#!/bin/bash
# Helper script to start Traefik with Nomad authentication

# Load Nomad token if available
if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
  source "${PARENT_DIR}/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Set Nomad address
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

echo "Attempting to start Traefik..."
if [ -n "\${NOMAD_TOKEN}" ]; then
  # Try with token
  NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job run "${JOB_DIR}/traefik.hcl" && echo "Traefik job started successfully via CLI" && exit 0
else
  # Try without token
  nomad job run "${JOB_DIR}/traefik.hcl" && echo "Traefik job started successfully" && exit 0
fi

echo "Failed to start Traefik job through Nomad. Check your authentication and permissions."
echo "You might need to ensure the nomad user has access to Docker:"
echo "  sudo synogroup --member docker nomad"
echo "  sudo chown root:docker /var/run/docker.sock"
exit 1
EOF
  
  # Create stop script with auth
  cat > "${PARENT_DIR}/bin/stop-traefik.sh" << EOF
#!/bin/bash
# Helper script to stop Traefik with Nomad authentication

# Load Nomad token if available
if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
  source "${PARENT_DIR}/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Set Nomad address
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

echo "Attempting to stop Traefik..."
if [ -n "\${NOMAD_TOKEN}" ]; then
  # Try with CLI
  NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job stop -purge traefik && echo "Traefik job stopped successfully via CLI" && exit 0
else
  # Try without token
  nomad job stop -purge traefik && echo "Traefik job stopped successfully" && exit 0
fi

echo "Failed to stop Traefik job through Nomad. Check your authentication."
exit 1
EOF
  
  # Create status script with auth
  cat > "${PARENT_DIR}/bin/traefik-status.sh" << EOF
#!/bin/bash
# Helper script to check Traefik status with Nomad authentication

# Load Nomad token if available
if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
  source "${PARENT_DIR}/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Set Nomad address
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

echo "Checking Traefik status..."

# Check status via CLI with token if available
if [ -n "\${NOMAD_TOKEN}" ]; then
  echo "Checking via Nomad CLI with token..."
  NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job status traefik
else
  # Try without token via CLI
  echo "Checking via Nomad CLI without token..."
  nomad job status traefik || echo "Failed to get job status. Check your Nomad authentication."
fi

# Check Traefik admin endpoint
echo ""
echo "Checking Traefik admin endpoint..."
if curl -s -f "http://localhost:${TRAEFIK_ADMIN_PORT:-8081}/ping" &>/dev/null; then
  echo "✅ Traefik admin endpoint is responding"
else
  echo "❌ Traefik admin endpoint is not responding"
fi

# Check ports
echo ""
echo "Checking Traefik ports..."
netstat -tuln | grep "${TRAEFIK_HTTP_PORT:-80}\|${TRAEFIK_HTTPS_PORT:-443}\|${TRAEFIK_ADMIN_PORT:-8081}" || echo "No Traefik ports found to be listening"

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

exit 0
EOF
  
  # Create troubleshooting script
  cat > "${PARENT_DIR}/bin/traefik-troubleshoot.sh" << EOF
#!/bin/bash
# Helper script for Traefik troubleshooting with Nomad authentication

# Load Nomad token if available
if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
  source "${PARENT_DIR}/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Set Nomad address
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

echo "=== Traefik Troubleshooting ==="
echo "Running comprehensive diagnostics..."

# Check Nomad status
echo "Checking Nomad status..."
if [ -n "\${NOMAD_TOKEN}" ]; then
  LEADER=\$(curl -s -H "X-Nomad-Token: \${NOMAD_TOKEN}" "\${NOMAD_ADDR}/v1/status/leader")
else
  LEADER=\$(curl -s "\${NOMAD_ADDR}/v1/status/leader")
fi
echo "Nomad leader: \${LEADER}"

# Check job status
echo "Checking Traefik job status..."
if [ -n "\${NOMAD_TOKEN}" ]; then
  NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job status traefik || echo "Failed to get job status"
else
  nomad job status traefik || echo "Failed to get job status"
fi

# Check allocations
echo "Checking Traefik allocations..."
if [ -n "\${NOMAD_TOKEN}" ]; then
  LATEST_ALLOC=\$(NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job allocs -latest traefik | grep -v ID | head -n1 | awk '{print \$1}')
  if [ -n "\${LATEST_ALLOC}" ]; then
    echo "Latest allocation: \${LATEST_ALLOC}"
    NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad alloc status \${LATEST_ALLOC} | grep -A 10 "Task States"
    # Try to get logs
    echo "Latest logs:"
    NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad alloc logs \${LATEST_ALLOC} traefik | tail -n 20
  else
    echo "No allocations found"
  fi
else
  echo "No token provided, skipping allocation check"
fi

# Check if Traefik process is running
echo "Checking for Traefik processes..."
ps aux | grep -i [t]raefik || echo "No Traefik process found"

# Check Docker containers
echo "Checking Docker containers..."
docker ps | grep traefik || echo "No Traefik container found"

# Check port status
echo "Checking port status..."
netstat -tuln | grep "${TRAEFIK_HTTP_PORT:-80}\|${TRAEFIK_HTTPS_PORT:-443}\|${TRAEFIK_ADMIN_PORT:-8081}" || echo "No Traefik ports found to be listening"

# Check certificate files
echo "Checking certificate files..."
ls -la "${DATA_DIR}/certificates/" || echo "Certificate directory not found"

# Check Traefik API
echo "Testing Traefik API..."
curl -s -f "http://localhost:${TRAEFIK_ADMIN_PORT:-8081}/api/rawdata" || echo "API not responding"

echo -e "\n=== Troubleshooting Information ==="
echo "1. If you're seeing authentication errors: Ensure your Nomad token is valid and has proper ACL permissions"
echo "2. If you're seeing 'missing drivers' error: Ensure Docker permissions are properly set up for the nomad user"
echo "3. If ports are already in use: Use alternative ports or stop conflicting services"
echo "4. If containers aren't starting: Check Docker daemon status and logs"
echo ""
echo "For more help, consult the documentation in docs/04-traefik-setup.md"
echo "=== End of Diagnostics ==="
EOF

  # Make scripts executable
  chmod +x "${PARENT_DIR}/bin/start-traefik.sh"
  chmod +x "${PARENT_DIR}/bin/stop-traefik.sh"
  chmod +x "${PARENT_DIR}/bin/traefik-status.sh"
  chmod +x "${PARENT_DIR}/bin/traefik-troubleshoot.sh"
  
  success "Helper scripts created in ${PARENT_DIR}/bin/"
}

# Function to display access information
show_access_info() {
  TRAEFIK_HOST=${TRAEFIK_HOST:-"traefik.${DOMAIN:-homelab.local}"}
  SYNOLOGY_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
  
  echo -e "\n${GREEN}==========================================================${NC}"
  echo -e "${GREEN}                Traefik Deployment Complete               ${NC}"
  echo -e "${GREEN}==========================================================${NC}"
  echo -e "\n${BLUE}Traefik is now available at:${NC}\n"
  echo -e "  * Dashboard: ${YELLOW}https://${TRAEFIK_HOST}${NC} or ${YELLOW}http://${SYNOLOGY_IP}:${TRAEFIK_ADMIN_PORT}${NC}"
  echo -e "  * HTTP Entry Point: ${YELLOW}http://${SYNOLOGY_IP}:${TRAEFIK_HTTP_PORT}${NC} (redirects to HTTPS)"
  echo -e "  * HTTPS Entry Point: ${YELLOW}https://${SYNOLOGY_IP}:${TRAEFIK_HTTPS_PORT}${NC}"
  echo -e "  * Health Check: ${YELLOW}http://${SYNOLOGY_IP}:${TRAEFIK_ADMIN_PORT}/ping${NC}"
  
  echo -e "\n${BLUE}Wildcard Certificate:${NC}"
  echo -e "  * Location: ${YELLOW}${CONFIG_DIR}/certs/wildcard.crt${NC}"
  echo -e "  * Mounted at: ${YELLOW}/etc/traefik/certs/wildcard.crt${NC} in the container"
  
  echo -e "\n${BLUE}Management Scripts:${NC}"
  echo -e "  * Start Traefik: ${YELLOW}${PARENT_DIR}/bin/start-traefik.sh${NC}"
  echo -e "  * Stop Traefik: ${YELLOW}${PARENT_DIR}/bin/stop-traefik.sh${NC}"
  echo -e "  * Check Status: ${YELLOW}${PARENT_DIR}/bin/traefik-status.sh${NC}"
  echo -e "  * Troubleshoot: ${YELLOW}${PARENT_DIR}/bin/traefik-troubleshoot.sh${NC}"
  
  echo -e "\n${BLUE}Nomad Authentication:${NC}"
  echo -e "  * Token File: ${YELLOW}${PARENT_DIR}/config/nomad_auth.conf${NC}"
  echo -e "  * To update token: ${YELLOW}echo \"NOMAD_TOKEN=your-new-token\" > ${PARENT_DIR}/config/nomad_auth.conf${NC}"
  
  echo -e "\n${BLUE}Troubleshooting:${NC}"
  echo -e "  * If you encounter 'missing drivers' error, ensure Docker permissions are correct:"
  echo -e "    - ${YELLOW}sudo synogroup --add docker${NC} # create docker group if needed"
  echo -e "    - ${YELLOW}sudo synogroup --member docker nomad${NC} # add nomad user to docker group"
  echo -e "    - ${YELLOW}sudo chown root:docker /var/run/docker.sock${NC} # fix socket permissions"
  echo -e "    - Restart Nomad after making these changes"
  
  echo -e "\n${GREEN}==========================================================${NC}"
}