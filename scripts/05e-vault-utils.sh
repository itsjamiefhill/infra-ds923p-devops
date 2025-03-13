#!/bin/bash
# 05e-vault-utils-helpers.sh
# Helper script functions for Vault deployment

# Function to create helper scripts
create_helper_scripts() {
  log "Creating helper scripts for Vault management..."
  
  # Create directory for scripts
  mkdir -p "${PARENT_DIR}/bin"
  
  # Create start script with auth
  cat > "${PARENT_DIR}/bin/start-vault.sh" << EOF
#!/bin/bash
# Helper script to start Vault with Nomad authentication

# Load Nomad token if available
if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
  source "${PARENT_DIR}/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Set Nomad address
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

echo "Attempting to start Vault..."
if [ -n "\${NOMAD_TOKEN}" ]; then
  # Try with token
  NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job run "${JOB_DIR}/vault.hcl" && echo "Vault job started successfully via CLI" && exit 0
else
  # Try without token
  nomad job run "${JOB_DIR}/vault.hcl" && echo "Vault job started successfully" && exit 0
fi

echo "Failed to start Vault job through Nomad. Check your authentication and permissions."
echo "You might need to ensure the nomad user has access to Docker:"
echo "  sudo synogroup --member docker nomad"
echo "  sudo chown root:docker /var/run/docker.sock"
exit 1
EOF
  
  # Create stop script with auth
  cat > "${PARENT_DIR}/bin/stop-vault.sh" << EOF
#!/bin/bash
# Helper script to stop Vault with Nomad authentication

# Load Nomad token if available
if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
  source "${PARENT_DIR}/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Set Nomad address
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

echo "Attempting to stop Vault..."
if [ -n "\${NOMAD_TOKEN}" ]; then
  # Try with CLI
  NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job stop -purge vault && echo "Vault job stopped successfully via CLI" && exit 0
else
  # Try without token
  nomad job stop -purge vault && echo "Vault job stopped successfully" && exit 0
fi

echo "Failed to stop Vault job through Nomad. Check your authentication."
exit 1
EOF
  
  # Create status script with auth
  cat > "${PARENT_DIR}/bin/vault-status.sh" << EOF
#!/bin/bash
# Helper script to check Vault status with Nomad authentication

# Load Nomad token if available
if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
  source "${PARENT_DIR}/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Set Nomad address
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

echo "Checking Vault status..."

# Check status via CLI with token if available
if [ -n "\${NOMAD_TOKEN}" ]; then
  echo "Checking via Nomad CLI with token..."
  NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job status vault
else
  # Try without token via CLI
  echo "Checking via Nomad CLI without token..."
  nomad job status vault || echo "Failed to get job status. Check your Nomad authentication."
fi

# Check Vault health endpoint
echo ""
echo "Checking Vault health endpoint..."
if curl -s -f "http://localhost:${VAULT_HTTP_PORT:-8200}/v1/sys/health?standbyok=true" &>/dev/null; then
  echo "✅ Vault health endpoint is responding"
  curl -s "http://localhost:${VAULT_HTTP_PORT:-8200}/v1/sys/health?standbyok=true" | grep initialized
else
  echo "❌ Vault health endpoint is not responding"
fi

# Get Vault seal status if it's running
if curl -s -f "http://localhost:${VAULT_HTTP_PORT:-8200}/v1/sys/health?standbyok=true" &>/dev/null; then
  echo ""
  echo "Checking Vault seal status..."
  
  # Get allocation ID
  if [ -n "\${NOMAD_TOKEN}" ]; then
    ALLOC_ID=\$(NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job allocs -latest vault | grep -v ID | head -1 | awk '{print \$1}')
  else
    ALLOC_ID=\$(nomad job allocs -latest vault | grep -v ID | head -1 | awk '{print \$1}')
  fi
  
  if [ -n "\${ALLOC_ID}" ]; then
    if [ -n "\${NOMAD_TOKEN}" ]; then
      NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad alloc exec -task vault \${ALLOC_ID} vault status || echo "Could not check Vault status"
    else
      nomad alloc exec -task vault \${ALLOC_ID} vault status || echo "Could not check Vault status"
    fi
  else
    echo "Could not determine Vault allocation ID"
  fi
fi

# Check ports
echo ""
echo "Checking Vault ports..."
netstat -tuln | grep "${VAULT_HTTP_PORT:-8200}" || echo "No Vault ports found to be listening"

exit 0
EOF
  
  # Create init script with auth
  cat > "${PARENT_DIR}/bin/vault-init.sh" << EOF
#!/bin/bash
# Helper script to initialize Vault with Nomad authentication

# Load Nomad token if available
if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
  source "${PARENT_DIR}/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Set Nomad address
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

echo "Checking Vault initialization status..."

# Check if Vault is running
if ! curl -s -f "http://localhost:${VAULT_HTTP_PORT:-8200}/v1/sys/health?standbyok=true" &>/dev/null; then
  echo "❌ Vault is not running or not responding. Please start Vault first."
  exit 1
fi

# Check if Vault is already initialized
INIT_STATUS=\$(curl -s "http://localhost:${VAULT_HTTP_PORT:-8200}/v1/sys/health?standbyok=true" | grep -o '"initialized":[^,]*' | cut -d':' -f2)
if [ "\$INIT_STATUS" = "true" ]; then
  echo "Vault is already initialized."
  echo "If you need to unseal it, run ./bin/vault-unseal.sh"
  exit 0
fi

# Get allocation ID
if [ -n "\${NOMAD_TOKEN}" ]; then
  ALLOC_ID=\$(NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job allocs -latest vault | grep -v ID | head -1 | awk '{print \$1}')
else
  ALLOC_ID=\$(nomad job allocs -latest vault | grep -v ID | head -1 | awk '{print \$1}')
fi

if [ -z "\$ALLOC_ID" ]; then
  echo "Error: Could not find Vault allocation"
  exit 1
fi

echo "Initializing Vault..."
if [ -n "\${NOMAD_TOKEN}" ]; then
  INIT_OUTPUT=\$(NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad alloc exec -task vault \$ALLOC_ID vault operator init)
else
  INIT_OUTPUT=\$(nomad alloc exec -task vault \$ALLOC_ID vault operator init)
fi

# Save the output to a secure file
echo "\$INIT_OUTPUT" > "${CONFIG_DIR}/vault/vault-init.txt"
chmod 600 "${CONFIG_DIR}/vault/vault-init.txt"

echo "Vault has been initialized."
echo "The unseal keys and root token have been saved to ${CONFIG_DIR}/vault/vault-init.txt"
echo "IMPORTANT: Keep this file secure! Anyone with these keys can access your Vault."

# Extract unseal keys and root token for immediate use
UNSEAL_KEYS=\$(echo "\$INIT_OUTPUT" | grep "Unseal Key" | awk '{print \$4}')
ROOT_TOKEN=\$(echo "\$INIT_OUTPUT" | grep "Root Token" | awk '{print \$3}')

# Unseal Vault automatically if requested
echo "Do you want to unseal Vault now? [y/N]"
read -r response
if [[ "\$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  echo "Unsealing Vault..."
  echo "\$UNSEAL_KEYS" | head -n3 | while read -r key; do
    echo "Using unseal key: \$key"
    if [ -n "\${NOMAD_TOKEN}" ]; then
      NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad alloc exec -task vault \$ALLOC_ID vault operator unseal \$key
    else
      nomad alloc exec -task vault \$ALLOC_ID vault operator unseal \$key
    fi
  done
  
  echo "Vault is now initialized and unsealed."
  echo "Root Token: \$ROOT_TOKEN"
  echo "You can use this token to log in to the UI or via the CLI."
  echo "To access the UI, visit: http://localhost:${VAULT_HTTP_PORT:-8200}/ui"
else
  echo "Vault is initialized but still sealed."
  echo "To unseal it later, run: ./bin/vault-unseal.sh"
fi

echo "Save this information in a secure location."
exit 0
EOF
  
  # Create unseal script with auth
  cat > "${PARENT_DIR}/bin/vault-unseal.sh" << EOF
#!/bin/bash
# Helper script to unseal Vault with Nomad authentication

# Load Nomad token if available
if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
  source "${PARENT_DIR}/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Set Nomad address
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

echo "Checking Vault seal status..."

# Check if Vault is running
if ! curl -s -f "http://localhost:${VAULT_HTTP_PORT:-8200}/v1/sys/health?standbyok=true" &>/dev/null; then
  echo "❌ Vault is not running or not responding. Please start Vault first."
  exit 1
fi

# Get allocation ID
if [ -n "\${NOMAD_TOKEN}" ]; then
  ALLOC_ID=\$(NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job allocs -latest vault | grep -v ID | head -1 | awk '{print \$1}')
else
  ALLOC_ID=\$(nomad job allocs -latest vault | grep -v ID | head -1 | awk '{print \$1}')
fi

if [ -z "\$ALLOC_ID" ]; then
  echo "Error: Could not find Vault allocation"
  exit 1
fi

# Check seal status
if [ -n "\${NOMAD_TOKEN}" ]; then
  SEAL_STATUS=\$(NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad alloc exec -task vault \$ALLOC_ID vault status 2>/dev/null || echo "error")
else
  SEAL_STATUS=\$(nomad alloc exec -task vault \$ALLOC_ID vault status 2>/dev/null || echo "error")
fi

if [[ "\$SEAL_STATUS" == *"error"* ]]; then
  echo "Failed to get Vault status. Make sure Vault is running and initialized."
  exit 1
fi

if [[ "\$SEAL_STATUS" == *"Sealed: false"* ]]; then
  echo "Vault is already unsealed."
  exit 0
fi

echo "Vault is sealed and needs to be unsealed."
echo "You will need at least 3 unseal keys from your initialization output."

if [ -f "${CONFIG_DIR}/vault/vault-init.txt" ]; then
  echo "Found init file at ${CONFIG_DIR}/vault/vault-init.txt"
  echo "Do you want to use these keys automatically? [y/N]"
  read -r response
  if [[ "\$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    UNSEAL_KEYS=\$(grep "Unseal Key" "${CONFIG_DIR}/vault/vault-init.txt" | awk '{print \$4}')
    echo "\$UNSEAL_KEYS" | head -n3 | while read -r key; do
      echo "Using unseal key: \$key"
      if [ -n "\${NOMAD_TOKEN}" ]; then
        NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad alloc exec -task vault \$ALLOC_ID vault operator unseal \$key
      else
        nomad alloc exec -task vault \$ALLOC_ID vault operator unseal \$key
      fi
    done
    echo "Vault should now be unsealed."
    exit 0
  fi
fi

# Manual unsealing process
for i in {1..3}; do
  echo "Enter unseal key #\$i:"
  read -r key
  
  echo "Applying unseal key #\$i..."
  if [ -n "\${NOMAD_TOKEN}" ]; then
    NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad alloc exec -task vault \$ALLOC_ID vault operator unseal \$key
  else
    nomad alloc exec -task vault \$ALLOC_ID vault operator unseal \$key
  fi
  
  # Check if we're unsealed after this key
  if [ -n "\${NOMAD_TOKEN}" ]; then
    SEAL_STATUS=\$(NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad alloc exec -task vault \$ALLOC_ID vault status)
  else
    SEAL_STATUS=\$(nomad alloc exec -task vault \$ALLOC_ID vault status)
  fi
  
  if [[ "\$SEAL_STATUS" == *"Sealed: false"* ]]; then
    echo "Vault is now unsealed!"
    exit 0
  fi
done

echo "Applied 3 unseal keys. Checking final status..."
if [ -n "\${NOMAD_TOKEN}" ]; then
  NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad alloc exec -task vault \$ALLOC_ID vault status
else
  nomad alloc exec -task vault \$ALLOC_ID vault status
fi

echo "Please run this script again if Vault is still sealed."
exit 0
EOF
  
  # Create troubleshooting script
  cat > "${PARENT_DIR}/bin/vault-troubleshoot.sh" << EOF
#!/bin/bash
# Helper script for Vault troubleshooting with Nomad authentication

# Load Nomad token if available
if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
  source "${PARENT_DIR}/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Set Nomad address
export NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

echo "=== Vault Troubleshooting ==="
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
echo "Checking Vault job status..."
if [ -n "\${NOMAD_TOKEN}" ]; then
  NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job status vault || echo "Failed to get job status"
else
  nomad job status vault || echo "Failed to get job status"
fi

# Check allocations
echo "Checking Vault allocations..."
if [ -n "\${NOMAD_TOKEN}" ]; then
  LATEST_ALLOC=\$(NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad job allocs -latest vault | grep -v ID | head -n1 | awk '{print \$1}')
  if [ -n "\${LATEST_ALLOC}" ]; then
    echo "Latest allocation: \${LATEST_ALLOC}"
    NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad alloc status \${LATEST_ALLOC} | grep -A 10 "Task States"
    # Try to get logs
    echo "Latest logs:"
    NOMAD_TOKEN="\${NOMAD_TOKEN}" nomad alloc logs \${LATEST_ALLOC} vault | tail -n 20
  else
    echo "No allocations found"
  fi
else
  echo "No token provided, skipping detailed allocation check"
  # Try basic alloc check without token
  nomad job allocs -latest vault || echo "Failed to get allocations"
fi

# Check Vault health
echo "Checking Vault health endpoint..."
curl -s "http://localhost:${VAULT_HTTP_PORT:-8200}/v1/sys/health?standbyok=true" || echo "Health endpoint not responding"

# Check Vault volume
echo "Checking Vault volume status..."
if nomad volume status vault_data &>/dev/null; then
  echo "✅ vault_data volume is registered in Nomad"
  nomad volume status vault_data | grep -A 3 "Read Allowed"
else
  echo "❌ vault_data volume is not registered in Nomad"
fi

# Check Vault data directory
echo "Checking Vault data directory..."
ls -la "${VAULT_DATA_DIR}" || echo "Cannot access Vault data directory"

# Check if Vault process is running
echo "Checking for Vault processes..."
ps aux | grep -i [v]ault || echo "No Vault process found"

# Check Docker containers
echo "Checking Docker containers..."
docker ps | grep vault || echo "No Vault container found"

# Check port status
echo "Checking port status..."
netstat -tuln | grep "${VAULT_HTTP_PORT:-8200}" || echo "No Vault ports found to be listening"

echo -e "\n=== Troubleshooting Information ==="
echo "1. If Vault is sealed: Use ./bin/vault-unseal.sh to unseal it"
echo "2. If Vault is not initialized: Use ./bin/vault-init.sh to initialize it"
echo "3. If you're seeing 'missing drivers' error: Ensure Docker permissions are properly set up for the nomad user"
echo "4. If you're seeing authentication errors: Ensure your Nomad token is valid"
echo "5. If Vault data directory has permission issues: Ensure it's owned by the nomad user"
echo ""
echo "For more help, consult the documentation in docs/05-vault-setup.md"
echo "=== End of Diagnostics ==="
EOF

  # Make scripts executable
  chmod +x "${PARENT_DIR}/bin/start-vault.sh"
  chmod +x "${PARENT_DIR}/bin/stop-vault.sh"
  chmod +x "${PARENT_DIR}/bin/vault-status.sh"
  chmod +x "${PARENT_DIR}/bin/vault-init.sh"
  chmod +x "${PARENT_DIR}/bin/vault-unseal.sh"
  chmod +x "${PARENT_DIR}/bin/vault-troubleshoot.sh"
  
  success "Helper scripts created in ${PARENT_DIR}/bin/"
}

# Function to display access information
show_access_info() {
  VAULT_HOST=${VAULT_HOST:-"vault.${DOMAIN:-homelab.local}"}
  SYNOLOGY_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
  
  echo -e "\n${GREEN}==========================================================${NC}"
  echo -e "${GREEN}                Vault Deployment Complete               ${NC}"
  echo -e "${GREEN}==========================================================${NC}"
  echo -e "\n${BLUE}Vault is now available at:${NC}\n"
  echo -e "  * UI: ${YELLOW}https://${VAULT_HOST}${NC} or ${YELLOW}http://${SYNOLOGY_IP}:${VAULT_HTTP_PORT}${NC}"
  echo -e "  * API: ${YELLOW}http://${SYNOLOGY_IP}:${VAULT_HTTP_PORT}/v1/sys/health${NC}"
  
  echo -e "\n${BLUE}Data Storage:${NC}"
  echo -e "  * Volume Name: ${YELLOW}vault_data${NC}"
  echo -e "  * Host Path: ${YELLOW}${VAULT_DATA_DIR}${NC}"
  echo -e "  * Container Path: ${YELLOW}/vault/data${NC}"
  
  if [ "${VAULT_DEV_MODE}" = "true" ]; then
    echo -e "\n${YELLOW}WARNING: Vault is running in DEVELOPMENT mode${NC}"
    echo -e "  * Root Token: ${YELLOW}root${NC}"
    echo -e "  * Data will be stored in memory and lost on restart"
    echo -e "  * This mode is NOT suitable for production"
  else
    echo -e "\n${BLUE}Initialization Required:${NC}"
    echo -e "  * Vault needs to be initialized before use"
    echo -e "  * Run: ${YELLOW}${PARENT_DIR}/bin/vault-init.sh${NC}"
    echo -e "  * This will generate unseal keys and a root token"
    echo -e "  * Store these securely - they are required to access Vault"
  fi
  
  echo -e "\n${BLUE}Management Scripts:${NC}"
  echo -e "  * Start Vault: ${YELLOW}${PARENT_DIR}/bin/start-vault.sh${NC}"
  echo -e "  * Stop Vault: ${YELLOW}${PARENT_DIR}/bin/stop-vault.sh${NC}"
  echo -e "  * Check Status: ${YELLOW}${PARENT_DIR}/bin/vault-status.sh${NC}"
  echo -e "  * Initialize: ${YELLOW}${PARENT_DIR}/bin/vault-init.sh${NC}"
  echo -e "  * Unseal: ${YELLOW}${PARENT_DIR}/bin/vault-unseal.sh${NC}"
  echo -e "  * Troubleshoot: ${YELLOW}${PARENT_DIR}/bin/vault-troubleshoot.sh${NC}"
  
  echo -e "\n${BLUE}Nomad Authentication:${NC}"
  echo -e "  * Token File: ${YELLOW}${PARENT_DIR}/config/nomad_auth.conf${NC}"
  
  echo -e "\n${BLUE}Next Steps:${NC}"
  echo -e "  1. Initialize Vault with ${YELLOW}./bin/vault-init.sh${NC}"
  echo -e "  2. Enable secret engines you need (kv, pki, etc.)"
  echo -e "  3. Configure authentication methods"
  echo -e "  4. Set up policies for access control"
  echo -e "  5. Integrate with other services in your platform"
  
  if [ "${VAULT_DEV_MODE}" != "true" ]; then
    echo -e "\n${BLUE}Important:${NC}"
    echo -e "  * After initialization, securely store your unseal keys and root token"
    echo -e "  * Vault will seal itself when the Nomad job or Docker container restarts"
    echo -e "  * You will need at least 3 unseal keys to unseal it again"
    echo -e "  * Consider setting up auto-unseal for production environments"
  fi
  
  echo -e "\n${GREEN}==========================================================${NC}"
}