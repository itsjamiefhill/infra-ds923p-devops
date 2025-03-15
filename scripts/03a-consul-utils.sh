#!/bin/bash
# 03a-consul-utils.sh
# Core utility functions for Consul deployment

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

# Function to set up Nomad SSL environment
setup_nomad_ssl() {
  log "Setting up Nomad SSL environment..."
  
  # Set default values for SSL environment
  export NOMAD_ADDR=https://127.0.0.1:4646
  export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
  export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
  export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem
  
  # Check if certificate files exist
  if [ ! -f "$NOMAD_CACERT" ] || [ ! -f "$NOMAD_CLIENT_CERT" ] || [ ! -f "$NOMAD_CLIENT_KEY" ]; then
    warn "Nomad SSL certificates not found at expected paths. SSL connections may fail."
  else
    success "Nomad SSL environment configured with certificates"
  fi
}

# Get the Synology's primary IP address
get_primary_ip() {
  # Try to determine the primary IP address
  PRIMARY_IP=$(ip route get 1 | awk '{print $7;exit}' 2>/dev/null)
  
  # If that doesn't work, try an alternative method
  if [ -z "$PRIMARY_IP" ]; then
    PRIMARY_IP=$(hostname -I | awk '{print $1}')
  fi
  
  # If we still don't have an IP, ask the user
  if [ -z "$PRIMARY_IP" ]; then
    log "Could not automatically determine IP address."
    echo -e "${YELLOW}"
    read -p "Please enter the IP address that Consul should use: " PRIMARY_IP
    echo -e "${NC}"
    
    if [ -z "$PRIMARY_IP" ]; then
      error "No IP address provided. Cannot continue."
    fi
  fi
  
  # Only return the IP address itself
  echo "$PRIMARY_IP"
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
    echo -e "${YELLOW}Please enter your Nomad management token (leave blank if not using auth):${NC}"
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
  
  # Set up Nomad environment
  if [ -n "${NOMAD_ADDR}" ]; then
    log "Using configured NOMAD_ADDR: ${NOMAD_ADDR}"
  else
    # Try to guess a reasonable default - use https if SSL is configured
    if [ -f "/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem" ]; then
      export NOMAD_ADDR="https://127.0.0.1:4646"
    else
      export NOMAD_ADDR="http://127.0.0.1:4646"
    fi
    log "NOMAD_ADDR not set, using default: ${NOMAD_ADDR}"
  fi
  
  # Prepare curl flags for SSL if needed
  CURL_FLAGS=""
  if [[ "${NOMAD_ADDR}" == https://* ]]; then
    if [ -f "/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem" ]; then
      CURL_FLAGS="--cacert /var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem"
      if [ -f "/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem" ] && [ -f "/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem" ]; then
        CURL_FLAGS="${CURL_FLAGS} --cert /var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem --key /var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem"
      fi
      log "Using SSL certificates for Nomad API connection"
    else
      CURL_FLAGS="-k"
      warn "Using insecure SSL connection mode (-k) because certificates not found"
    fi
  fi
  
  # Direct API check (doesn't require authentication for basic status)
  if curl -s -f ${CURL_FLAGS} "${NOMAD_ADDR}/v1/status/leader" &>/dev/null; then
    log "Nomad API is reachable at ${NOMAD_ADDR}"
  else
    warn "Cannot connect to Nomad API at ${NOMAD_ADDR}"
    warn "Please check if Nomad is running and accessible."
    return 1
  fi
  
  # Try authenticated operations (will need the token)
  if [ -n "${NOMAD_TOKEN}" ]; then
    if curl -s -f ${CURL_FLAGS} -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR}/v1/jobs" &>/dev/null; then
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