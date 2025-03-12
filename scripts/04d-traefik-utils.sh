#!/bin/bash
# 04d-traefik-utils.sh
# Deployment functions for Traefik deployment

# Function to deploy Traefik job
deploy_traefik() {
  log "Deploying Traefik job to Nomad..."
  
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
  log "Submitting Traefik job to Nomad..."
  
  # First, purge any existing job to ensure clean state
  if [ -n "${NOMAD_TOKEN}" ]; then
    log "Stopping any existing Traefik job..."
    NOMAD_TOKEN="${NOMAD_TOKEN}" nomad job stop -purge traefik 2>/dev/null || true
  else
    log "Stopping any existing Traefik job..."
    nomad job stop -purge traefik 2>/dev/null || true
  fi
  
  # Wait a moment for the job to be purged
  sleep 2
  
  # Deploy the job
  local job_file="${JOB_DIR}/traefik.hcl"
  local deploy_result=0
  
  if [ -n "${NOMAD_TOKEN}" ]; then
    log "Running job with authentication token..."
    NOMAD_TOKEN="${NOMAD_TOKEN}" nomad job run "${job_file}" || deploy_result=$?
  else
    log "Running job without authentication token..."
    nomad job run "${job_file}" || deploy_result=$?
  fi
  
  if [ ${deploy_result} -ne 0 ]; then
    warn "Failed to deploy Traefik job to Nomad (exit code: ${deploy_result})"
    
    # Check for "missing drivers" error
    if nomad job status traefik 2>&1 | grep -q "missing drivers"; then
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
          "${PARENT_DIR}/bin/traefik-docker-run.sh"
        fi
      fi
      
      warn "Deployment through Nomad failed. Please fix the permissions and try again."
      return 1
    else
      warn "Deployment failed for an unknown reason. Check Nomad logs for details."
      return 1
    fi
  fi
  
  # Wait for Traefik to be ready
  log "Waiting for Traefik to be ready..."
  sleep 10
  
  # Check if Traefik job is running
  local job_status=""
  if [ -n "${NOMAD_TOKEN}" ]; then
    job_status=$(NOMAD_TOKEN="${NOMAD_TOKEN}" nomad job status traefik | grep -A 1 "Status" | tail -n 1)
  else
    job_status=$(nomad job status traefik | grep -A 1 "Status" | tail -n 1)
  fi
  
  if [[ "${job_status}" == *"running"* ]]; then
    success "Traefik job is running successfully in Nomad"
  else
    warn "Traefik job status is not 'running'. Current status: ${job_status}"
    warn "Check Nomad UI or job logs for more details."
  fi
  
  # Wait a bit more for Traefik to start up completely
  log "Waiting a bit more for Traefik to initialize..."
  sleep 15
  
  # Check if Traefik admin endpoint is responding
  if curl -s -f "http://localhost:${TRAEFIK_ADMIN_PORT}/ping" &>/dev/null; then
    success "Traefik admin endpoint is responding"
  else
    warn "Traefik admin endpoint is not responding yet."
    
    # If we reached this point but a TCP check is still failing, check what might be wrong
    if ! command -v nc &>/dev/null || ! nc -z localhost ${TRAEFIK_ADMIN_PORT} &>/dev/null; then
      warn "Traefik admin port ${TRAEFIK_ADMIN_PORT} is not accessible via TCP"
      warn "This might explain health check failures. Checking for port conflicts..."
      
      # Check if another process is using the port
      if netstat -tuln | grep -q ":${TRAEFIK_ADMIN_PORT}\s"; then
        warn "Another process is already using port ${TRAEFIK_ADMIN_PORT}. Consider using a different port."
        netstat -tuln | grep ":${TRAEFIK_ADMIN_PORT}\s" || true
      fi
      
      # Check Docker container logs
      log "Checking Traefik container logs..."
      if [ -n "${NOMAD_TOKEN}" ]; then
        local ALLOC_ID=$(NOMAD_TOKEN="${NOMAD_TOKEN}" nomad job allocs -latest traefik | grep -v ID | head -1 | awk '{print $1}')
        if [ -n "${ALLOC_ID}" ]; then
          log "Latest allocation: ${ALLOC_ID}"
          log "Traefik logs:"
          NOMAD_TOKEN="${NOMAD_TOKEN}" nomad alloc logs "${ALLOC_ID}" traefik || warn "Failed to retrieve logs"
        fi
      fi
    fi
    
    log "Traefik service started but admin endpoint not responding yet."
    log "This might be normal if Traefik is still starting up."
    log "Try accessing it manually at http://localhost:${TRAEFIK_ADMIN_PORT}/ping after a few minutes."
    log "Run ./bin/traefik-troubleshoot.sh for more detailed diagnostics."
  fi
  
  return 0
}

# Function to create Docker fallback deployment
create_docker_fallback() {
  log "Creating Docker fallback deployment script..."
  
  # Get configuration values
  TRAEFIK_HTTP_PORT=${TRAEFIK_HTTP_PORT:-80}
  TRAEFIK_HTTPS_PORT=${TRAEFIK_HTTPS_PORT:-443}
  TRAEFIK_ADMIN_PORT=${TRAEFIK_ADMIN_PORT:-8081}
  TRAEFIK_VERSION=${TRAEFIK_VERSION:-"v2.9"}
  TRAEFIK_HOST=${TRAEFIK_HOST:-"traefik.${DOMAIN:-homelab.local}"}
  
  mkdir -p "${PARENT_DIR}/bin"
  
  # Create the Docker run script
  cat > "${PARENT_DIR}/bin/traefik-docker-run.sh" << EOF
#!/bin/bash
# Direct Docker deployment for Traefik
# Created as a fallback due to Nomad Docker driver issues

# Stop any existing container
docker stop traefik 2>/dev/null || true
docker rm traefik 2>/dev/null || true

# Create traefik config directory if it doesn't exist
mkdir -p "${PARENT_DIR}/config/traefik/dynamic"

# Create traefik.toml
cat > "${PARENT_DIR}/config/traefik/traefik.toml" << EOT
[entryPoints]
  [entryPoints.web]
    address = ":${TRAEFIK_HTTP_PORT}"
    [entryPoints.web.http.redirections.entryPoint]
      to = "websecure"
      scheme = "https"
  
  [entryPoints.websecure]
    address = ":${TRAEFIK_HTTPS_PORT}"
  
  [entryPoints.traefik]
    address = ":${TRAEFIK_ADMIN_PORT}"

[api]
  dashboard = true
  insecure = true

[providers.file]
  directory = "/etc/traefik/dynamic"
  watch = true

[log]
  level = "DEBUG"

[accessLog]

[tls]
  [[tls.certificates]]
    certFile = "/etc/traefik/certs/wildcard.crt"
    keyFile = "/etc/traefik/certs/wildcard.key"
EOT

# Create dashboard configuration
cat > "${PARENT_DIR}/config/traefik/dynamic/dashboard.toml" << EOT
[http.routers.dashboard]
  rule = "Host(\\\`${TRAEFIK_HOST}\\\`)"
  service = "api@internal"
  entryPoints = ["websecure"]
  tls = true
EOT

echo "Starting Traefik container with Docker..."
docker run -d \\
  --name traefik \\
  --restart unless-stopped \\
  -p ${TRAEFIK_HTTP_PORT}:${TRAEFIK_HTTP_PORT} \\
  -p ${TRAEFIK_HTTPS_PORT}:${TRAEFIK_HTTPS_PORT} \\
  -p ${TRAEFIK_ADMIN_PORT}:${TRAEFIK_ADMIN_PORT} \\
  -v "${PARENT_DIR}/config/traefik/traefik.toml:/etc/traefik/traefik.toml" \\
  -v "${PARENT_DIR}/config/traefik/dynamic:/etc/traefik/dynamic" \\
  -v "${DATA_DIR}/certificates:/etc/traefik/certs:ro" \\
  traefik:${TRAEFIK_VERSION}

echo "Traefik started with Docker. Dashboard available at https://${TRAEFIK_HOST} or http://localhost:${TRAEFIK_ADMIN_PORT}"
EOF

  chmod +x "${PARENT_DIR}/bin/traefik-docker-run.sh"
  
  # Create stop script
  cat > "${PARENT_DIR}/bin/traefik-docker-stop.sh" << EOF
#!/bin/bash
# Stop the Traefik container started with Docker

echo "Stopping Traefik container..."
docker stop traefik
docker rm traefik
echo "Traefik container stopped and removed."
EOF

  chmod +x "${PARENT_DIR}/bin/traefik-docker-stop.sh"
  
  log "Created Docker fallback scripts in ${PARENT_DIR}/bin/"
}