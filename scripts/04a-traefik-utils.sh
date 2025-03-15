#!/bin/bash
# 04a-traefik-utils.sh
# Core utility functions for Traefik deployment

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display status messages
log() {
  echo -e "${BLUE}[INFO]${NC} $1"
  if [ -f "${LOG_FILE}" ]; then
    echo "[INFO] $(date): $1" >> "${LOG_FILE}"
  fi
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
  if [ -f "${LOG_FILE}" ]; then
    echo "[SUCCESS] $(date): $1" >> "${LOG_FILE}"
  fi
}

warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
  if [ -f "${LOG_FILE}" ]; then
    echo "[WARNING] $(date): $1" >> "${LOG_FILE}"
  fi
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
  if [ -f "${LOG_FILE}" ]; then
    echo "[ERROR] $(date): $1" >> "${LOG_FILE}"
  fi
  exit 1
}

# Function to handle Nomad authentication
setup_nomad_auth() {
  log "Setting up Nomad authentication..."
  
  # Check if we have a Nomad auth config file
  NOMAD_AUTH_FILE="${PARENT_DIR}/config/nomad_auth.conf"
  
  if [ -f "${NOMAD_AUTH_FILE}" ]; then
    log "Loading Nomad authentication from ${NOMAD_AUTH_FILE}"
    source "${NOMAD_AUTH_FILE}"
  fi
  
  # If NOMAD_TOKEN is still not set, prompt for it
  if [ -z "${NOMAD_TOKEN}" ]; then
    log "Nomad token not found. You will need to provide a management token."
    echo -e "${YELLOW}Please enter your Nomad management token:${NC}"
    read -r NOMAD_TOKEN
    
    if [ -z "${NOMAD_TOKEN}" ]; then
      warn "No token provided. Will try to continue without authentication."
    else
      # Save the token for future use
      mkdir -p "${PARENT_DIR}/config"
      echo "NOMAD_TOKEN=${NOMAD_TOKEN}" > "${NOMAD_AUTH_FILE}"
      chmod 600 "${NOMAD_AUTH_FILE}"  # Secure the token file
      log "Nomad token saved to ${NOMAD_AUTH_FILE}"
    fi
  fi
  
  # Export the token for the Nomad CLI
  if [ -n "${NOMAD_TOKEN}" ]; then
    export NOMAD_TOKEN
    log "Nomad token set in environment"
  fi
  
  # Setup SSL environment if not already set
  if [ -z "${NOMAD_ADDR}" ]; then
    # Default to https if SSL certs exist
    if [ -f "/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem" ]; then
      export NOMAD_ADDR="https://127.0.0.1:4646"
      export NOMAD_CACERT="/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem"
      export NOMAD_CLIENT_CERT="/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem"
      export NOMAD_CLIENT_KEY="/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem"
      log "SSL environment configured for Nomad:"
      log "NOMAD_ADDR=${NOMAD_ADDR}"
      log "NOMAD_CACERT=${NOMAD_CACERT}"
    else
      export NOMAD_ADDR="http://127.0.0.1:4646"
      log "SSL certificates not found, using non-SSL connection: ${NOMAD_ADDR}"
    fi
  else
    log "Using existing NOMAD_ADDR: ${NOMAD_ADDR}"
  fi
  
  # Test if we can authenticate with Nomad
  if ! nomad status 2>/dev/null; then
    warn "Could not authenticate with Nomad using the provided token."
    warn "Will attempt to continue, but you may encounter permission issues."
    return 1
  fi
  
  success "Successfully authenticated with Nomad"
  return 0
}

# Function to check if nomad user is in docker group
check_docker_group_membership() {
  # Get the docker group ID if it exists
  local docker_gid=$(getent group docker 2>/dev/null | cut -d: -f3)
  local docker_group_exists=$?
  
  # If getent fails or doesn't find docker group
  if [ $docker_group_exists -ne 0 ] || [ -z "$docker_gid" ]; then
    log "Docker group not found via getent. Checking with grep..."
    # Try alternative method to find docker group
    if grep -q "^docker:" /etc/group; then
      docker_gid=$(grep "^docker:" /etc/group | cut -d: -f3)
      log "Found docker group with GID: ${docker_gid}"
    elif grep -q ":docker:" /etc/group; then
      docker_gid=$(grep ":docker:" /etc/group | cut -d: -f3)
      log "Found docker group with GID: ${docker_gid}"
    else
      log "Docker group not found in /etc/group"
      return 1  # Docker group doesn't exist
    fi
  fi
  
  log "Detected docker group with GID: ${docker_gid}"
  
  # Check if nomad user exists
  if ! id nomad &>/dev/null; then
    log "Nomad user not found on system"
    return 1
  fi
  
  # Get nomad's groups
  local nomad_groups=$(id nomad 2>/dev/null)
  
  # Check if nomad user is in docker group by GID or name
  if echo "$nomad_groups" | grep -qE "groups=.*(^|,)${docker_gid}(,|$)|groups=.*docker"; then
    log "Nomad user is in docker group"
    return 0  # Nomad is in docker group
  else
    log "Nomad user is not in docker group"
    log "Nomad user groups: ${nomad_groups}"
    return 1  # Nomad is not in docker group
  fi
}

# Function to check Docker driver permissions
check_docker_permissions() {
  log "Checking Docker driver permissions..."
  
  # Check if Docker is accessible
  if ! docker info &>/dev/null; then
    warn "Docker is not accessible by the current user"
    
    # Check if docker.sock has the right permissions
    local sock_perms=$(ls -la /var/run/docker.sock 2>/dev/null | awk '{print $1, $3, $4}' || echo "")
    log "Docker socket permissions: ${sock_perms}"
    
    # Check if nomad user is in docker group
    if ! check_docker_group_membership; then
      warn "The 'nomad' user does not appear to be in the 'docker' group"
      echo -e "${YELLOW}Do you want to fix Docker permissions automatically? [y/N]${NC}"
      read -r fix_perms
      
      if [[ "$fix_perms" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        log "Fixing Docker permissions..."
        
        # Add docker group if it doesn't exist
        if ! getent group docker &>/dev/null; then
          sudo synogroup --add docker || warn "Failed to create docker group"
          log "Created docker group"
        fi
        
        # Add nomad user to docker group
        sudo synogroup --member docker nomad || warn "Failed to add nomad to docker group"
        log "Added nomad user to docker group"
        
        # Fix socket permissions
        sudo chown root:docker /var/run/docker.sock || warn "Failed to change docker.sock ownership"
        log "Changed docker.sock ownership to root:docker"
        
        log "Docker permissions fixed. Note that you may need to restart Nomad for changes to take effect."
        echo -e "${YELLOW}Do you want to restart Nomad now? [y/N]${NC}"
        read -r restart_nomad
        
        if [[ "$restart_nomad" =~ ^([yY][eE][sS]|[yY])$ ]]; then
          # Different ways to restart Nomad depending on the system
          if command -v systemctl &>/dev/null && systemctl list-unit-files | grep -q nomad; then
            log "Restarting Nomad using systemctl..."
            sudo systemctl restart nomad
          elif [ -f "/etc/init.d/nomad" ]; then
            log "Restarting Nomad using init script..."
            sudo /etc/init.d/nomad restart
          elif [ -f "/usr/local/etc/rc.d/nomad" ]; then 
            log "Restarting Nomad using Synology rc.d script..."
            sudo /usr/local/etc/rc.d/nomad restart
          else
            log "Attempting to restart Nomad via process signals..."
            sudo pkill -HUP nomad
          fi
          
          log "Waiting for Nomad to restart..."
          sleep 10
        fi
      fi
    else
      log "Nomad user is in the docker group, but Docker socket permissions may be incorrect"
      log "Consider running: sudo chown root:docker /var/run/docker.sock"
    fi
  else
    log "Docker is accessible - permissions appear to be correctly configured"
  fi
}

# Function to check Nomad connectivity with authentication
check_nomad_connectivity() {
  log "Checking Nomad connectivity..."
  
  # NOMAD_ADDR should be already set by setup_nomad_auth
  log "Using NOMAD_ADDR: ${NOMAD_ADDR}"
  
  # Prepare curl command with SSL options if needed
  CURL_OPTS=""
  if [[ "${NOMAD_ADDR}" == https://* ]] && [ -n "${NOMAD_CACERT}" ]; then
    CURL_OPTS="--cacert ${NOMAD_CACERT}"
    
    # Add client certificate if available
    if [ -n "${NOMAD_CLIENT_CERT}" ] && [ -n "${NOMAD_CLIENT_KEY}" ]; then
      CURL_OPTS="${CURL_OPTS} --cert ${NOMAD_CLIENT_CERT} --key ${NOMAD_CLIENT_KEY}"
    fi
    
    log "Using SSL for Nomad API connection"
  fi
  
  # Direct API check (doesn't require authentication for basic status)
  if curl -s -f ${CURL_OPTS} "${NOMAD_ADDR}/v1/status/leader" &>/dev/null; then
    log "Nomad API is reachable at ${NOMAD_ADDR}"
  else
    warn "Cannot connect to Nomad API at ${NOMAD_ADDR}"
    warn "Please check if Nomad is running and accessible."
    return 1
  fi
  
  # Try authenticated operations (will need the token)
  if [ -n "${NOMAD_TOKEN}" ]; then
    if curl -s -f ${CURL_OPTS} -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR}/v1/jobs" &>/dev/null; then
      log "Successfully authenticated with Nomad API"
      return 0
    else
      warn "Authentication with Nomad API failed. Token may be invalid."
      return 1
    fi
  else
    warn "No Nomad token provided. Some operations may fail."
    return 1
  fi
}

# Function to check Traefik port availability
check_port_availability() {
  log "Checking if Traefik ports are available..."
  
  # Define the ports to check
  local HTTP_PORT=${TRAEFIK_HTTP_PORT:-80}
  local HTTPS_PORT=${TRAEFIK_HTTPS_PORT:-443}
  local ADMIN_PORT=${TRAEFIK_ADMIN_PORT:-8081}
  
  # Check if ports are already in use
  local PORT_CONFLICTS=()
  
  if netstat -tuln | grep -q ":${HTTP_PORT}[^0-9]"; then
    PORT_CONFLICTS+=("${HTTP_PORT}")
  fi
  
  if netstat -tuln | grep -q ":${HTTPS_PORT}[^0-9]"; then
    PORT_CONFLICTS+=("${HTTPS_PORT}")
  fi
  
  if netstat -tuln | grep -q ":${ADMIN_PORT}[^0-9]"; then
    PORT_CONFLICTS+=("${ADMIN_PORT}")
  fi
  
  if [ ${#PORT_CONFLICTS[@]} -gt 0 ]; then
    warn "Some ports required by Traefik are already in use: ${PORT_CONFLICTS[*]}"
    
    # Ask if user wants to use alternative ports
    echo -e "${YELLOW}Would you like to use alternative ports for Traefik? [y/N]${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      # Suggest alternative ports
      if [[ " ${PORT_CONFLICTS[*]} " =~ " ${HTTP_PORT} " ]]; then
        echo -e "${YELLOW}Port ${HTTP_PORT} is in use. Please specify an alternative port for HTTP:${NC}"
        read -r TRAEFIK_HTTP_PORT
      fi
      
      if [[ " ${PORT_CONFLICTS[*]} " =~ " ${HTTPS_PORT} " ]]; then
        echo -e "${YELLOW}Port ${HTTPS_PORT} is in use. Please specify an alternative port for HTTPS:${NC}"
        read -r TRAEFIK_HTTPS_PORT
      fi
      
      if [[ " ${PORT_CONFLICTS[*]} " =~ " ${ADMIN_PORT} " ]]; then
        echo -e "${YELLOW}Port ${ADMIN_PORT} is in use. Please specify an alternative port for Admin:${NC}"
        read -r TRAEFIK_ADMIN_PORT
      fi
      
      log "Using alternative ports: HTTP=${TRAEFIK_HTTP_PORT}, HTTPS=${TRAEFIK_HTTPS_PORT}, Admin=${TRAEFIK_ADMIN_PORT}"
    else
      warn "Continuing with default ports despite conflicts. This may cause issues."
    fi
  else
    log "All required ports are available."
  fi
}