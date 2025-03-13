#!/bin/bash
# 05d-vault-utils-deploy.sh
# Deployment functions for Vault deployment

# Function to deploy Vault job
deploy_vault() {
  log "Deploying Vault job to Nomad..."
  
  # Check Docker permissions
  check_docker_permissions
  
  # Check Nomad connectivity first
  if ! check_nomad_connectivity; then
    warn "Nomad connectivity issues detected."
    echo -e "${YELLOW}Do you want to continue with deployment anyway? [y/N]${NC}"
    read -r response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      error "Deployment aborted due to Nomad connectivity issues."
    fi
  fi
  
  # Deploy the job
  log "Submitting Vault job to Nomad..."
  
  # First, purge any existing job to ensure clean state
  if [ -n "${NOMAD_TOKEN}" ]; then
    log "Stopping any existing Vault job..."
    NOMAD_TOKEN="${NOMAD_TOKEN}" nomad job stop -purge vault 2>/dev/null || true
  else
    log "Stopping any existing Vault job..."
    nomad job stop -purge vault 2>/dev/null || true
  fi
  
  # Wait a moment for the job to be purged
  sleep 2
  
  # Deploy the job
  local job_file="${JOB_DIR}/vault.hcl"
  local deploy_result=0
  
  if [ -n "${NOMAD_TOKEN}" ]; then
    log "Running job with authentication token..."
    NOMAD_TOKEN="${NOMAD_TOKEN}" nomad job run "${job_file}" || deploy_result=$?
  else
    log "Running job without authentication token..."
    nomad job run "${job_file}" || deploy_result=$?
  fi
  
  if [ ${deploy_result} -ne 0 ]; then
    warn "Failed to deploy Vault job to Nomad (exit code: ${deploy_result})"
    
    # Check for "missing drivers" error
    if nomad job status vault 2>&1 | grep -q "missing drivers"; then
      warn "Detected 'missing drivers' error. The Docker driver is not available to Nomad."
      warn "Please ensure that:"
      warn "1. The nomad user is in the docker group: sudo synogroup --member docker nomad"
      warn "2. The Docker socket has the right permissions: sudo chown root:docker /var/run/docker.sock"
      warn "3. Nomad has been restarted after making these changes"
      
      # Offer to create a direct Docker deployment as fallback
      echo -e "${YELLOW}Would you like to create a Docker deployment script as fallback? [y/N]${NC}"
      read -r create_docker
      if [[ "$create_docker" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        create_docker_fallback
        echo -e "${YELLOW}Would you like to run the Docker fallback script now? [y/N]${NC}"
        read -r run_docker
        if [[ "$run_docker" =~ ^([yY][eE][sS]|[yY])$ ]]; then
          "${PARENT_DIR}/bin/vault-docker-run.sh"
        fi
      fi
      
      warn "Deployment through Nomad failed. Please fix the permissions and try again."
      return 1
    else
      warn "Deployment failed for an unknown reason. Check Nomad logs for details."
      return 1
    fi
  fi
  
  # Wait for Vault to be ready
  log "Waiting for Vault to be ready..."
  sleep 10
  
  # Check if Vault job is running
  local job_status=""
  if [ -n "${NOMAD_TOKEN}" ]; then
    job_status=$(NOMAD_TOKEN="${NOMAD_TOKEN}" nomad job status vault | grep -A 1 "Status" | tail -n 1)
  else
    job_status=$(nomad job status vault | grep -A 1 "Status" | tail -n 1)
  fi
  
  if [[ "${job_status}" == *"running"* ]]; then
    success "Vault job is running successfully in Nomad"
  else
    warn "Vault job status is not 'running'. Current status: ${job_status}"
    warn "Check Nomad UI or job logs for more details."
  fi
  
  # Wait a bit more for Vault to start up completely
  log "Waiting a bit more for Vault to initialize..."
  sleep 15
  
  # Check if Vault endpoint is responding
  if curl -s -f "http://localhost:${VAULT_HTTP_PORT}/v1/sys/health?standbyok=true" &>/dev/null; then
    success "Vault endpoint is responding"
  else
    warn "Vault endpoint is not responding yet."
    
    # If we reached this point but a TCP check is still failing, check what might be wrong
    if ! command -v nc &>/dev/null || ! nc -z localhost ${VAULT_HTTP_PORT} &>/dev/null; then
      warn "Vault port ${VAULT_HTTP_PORT} is not accessible via TCP"
      warn "This might explain health check failures. Checking for port conflicts..."
      
      # Check if another process is using the port
      if netstat -tuln | grep -q ":${VAULT_HTTP_PORT}\s"; then
        warn "Another process is already using port ${VAULT_HTTP_PORT}. Consider using a different port."
        netstat -tuln | grep ":${VAULT_HTTP_PORT}\s" || true
      fi
      
      # Check Docker container logs
      log "Checking Vault container logs..."
      if [ -n "${NOMAD_TOKEN}" ]; then
        local ALLOC_ID=$(NOMAD_TOKEN="${NOMAD_TOKEN}" nomad job allocs -latest vault | grep -v ID | head -1 | awk '{print $1}')
        if [ -n "${ALLOC_ID}" ]; then
          log "Latest allocation: ${ALLOC_ID}"
          log "Vault logs:"
          NOMAD_TOKEN="${NOMAD_TOKEN}" nomad alloc logs "${ALLOC_ID}" vault || warn "Failed to retrieve logs"
        fi
      fi
    fi
    
    log "Vault service started but endpoint not responding yet."
    log "This might be normal if Vault is still starting up."
    log "Try accessing it manually at http://localhost:${VAULT_HTTP_PORT}/v1/sys/health after a few minutes."
    log "Run ./bin/vault-troubleshoot.sh for more detailed diagnostics."
  fi
  
  # Provide info about initialization if needed
  if [ "${VAULT_DEV_MODE}" != "true" ]; then
    log "Vault is deployed but needs to be initialized. Use the following commands after deployment:"
    log "1. Get the allocation ID: nomad job allocs -latest vault"
    log "2. Initialize Vault: nomad alloc exec -task vault <alloc_id> vault operator init"
    log "3. Unseal Vault: nomad alloc exec -task vault <alloc_id> vault operator unseal <unseal_key>"
    log "Or use the helper script: ${CONFIG_DIR}/vault/init.sh"
  else
    log "Vault is deployed in development mode with initial root token 'root'"
  fi
  
  return 0
}

# Function to create Docker fallback deployment
create_docker_fallback() {
  log "Creating Docker fallback deployment script..."
  
  # Get configuration values
  VAULT_HTTP_PORT=${VAULT_HTTP_PORT:-8200}
  VAULT_IMAGE=${VAULT_IMAGE:-"hashicorp/vault:latest"}
  VAULT_DEV_MODE=${VAULT_DEV_MODE:-"false"}
  
  mkdir -p "${PARENT_DIR}/bin"
  
  # Create the Docker run script
  cat > "${PARENT_DIR}/bin/vault-docker-run.sh" << EOF
#!/bin/bash
# Direct Docker deployment for Vault
# Created as a fallback due to Nomad Docker driver issues

# Stop any existing container
docker stop vault 2>/dev/null || true
docker rm vault 2>/dev/null || true

# Create vault config directory if it doesn't exist
mkdir -p "${PARENT_DIR}/config/vault"

# Create vault.hcl
cat > "${PARENT_DIR}/config/vault/vault.hcl" << EOT
storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address = "0.0.0.0:${VAULT_HTTP_PORT}"
  tls_disable = true
}

ui = true
disable_mlock = true
api_addr = "http://0.0.0.0:${VAULT_HTTP_PORT}"
EOT

echo "Starting Vault container with Docker..."

EOF

  # Add different run commands based on dev mode
  if [ "${VAULT_DEV_MODE}" = "true" ]; then
    cat >> "${PARENT_DIR}/bin/vault-docker-run.sh" << EOF
# Starting in development mode
docker run -d \\
  --name vault \\
  --restart unless-stopped \\
  -p ${VAULT_HTTP_PORT}:${VAULT_HTTP_PORT} \\
  -e VAULT_DEV_ROOT_TOKEN_ID=root \\
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:${VAULT_HTTP_PORT} \\
  ${VAULT_IMAGE} \\
  server -dev

echo "Vault started in DEVELOPMENT mode with Docker."
echo "Use root token: root"
echo "UI available at: http://localhost:${VAULT_HTTP_PORT}/ui"
echo "WARNING: Data will be lost when container is removed!"
EOF
  else
    cat >> "${PARENT_DIR}/bin/vault-docker-run.sh" << EOF
# Starting in standard mode
docker run -d \\
  --name vault \\
  --restart unless-stopped \\
  --cap-add=IPC_LOCK \\
  -p ${VAULT_HTTP_PORT}:${VAULT_HTTP_PORT} \\
  -v "${PARENT_DIR}/config/vault/vault.hcl:/vault/config/vault.hcl" \\
  -v "${VAULT_DATA_DIR}:/vault/data" \\
  ${VAULT_IMAGE} \\
  server

echo "Vault started with Docker. You need to initialize and unseal it."
echo "To initialize: docker exec vault vault operator init"
echo "To unseal: docker exec vault vault operator unseal <unseal_key>"
echo "UI available at: http://localhost:${VAULT_HTTP_PORT}/ui"
EOF
  fi

  chmod +x "${PARENT_DIR}/bin/vault-docker-run.sh"
  
  # Create stop script
  cat > "${PARENT_DIR}/bin/vault-docker-stop.sh" << EOF
#!/bin/bash
# Stop the Vault container started with Docker

echo "Stopping Vault container..."
docker stop vault
docker rm vault
echo "Vault container stopped and removed."
EOF

  chmod +x "${PARENT_DIR}/bin/vault-docker-stop.sh"
  
  log "Created Docker fallback scripts in ${PARENT_DIR}/bin/"
}