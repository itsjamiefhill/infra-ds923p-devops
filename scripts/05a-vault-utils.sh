#!/bin/bash
# 05a-vault-utils-core.sh
# Core utility functions for Vault deployment

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

# Function to check prerequisites
check_prerequisites() {
  log "Checking prerequisites for Vault deployment..."
  
  # Check if nomad is installed
  if ! command -v nomad &> /dev/null; then
    error "Nomad is not installed. Please install Nomad first."
  fi
  
  # Check if docker is installed
  if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install Docker first."
  fi
  
  # Check for previous Vault installation
  if nomad job status vault &>/dev/null; then
    warn "A Vault job already exists in Nomad."
    echo -e "${YELLOW}Do you want to replace the existing Vault job? [y/N]${NC}"
    read -r response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      error "Vault deployment aborted by user."
    fi
    log "Will replace existing Vault job."
  fi
  
  # Check if Consul is running (recommended for Vault)
  if ! curl -s -f "http://localhost:8500/v1/status/leader" &>/dev/null; then
    warn "Consul seems to be unavailable. While not strictly required, it's recommended to have Consul running for Vault."
    echo -e "${YELLOW}Do you want to continue without Consul? [y/N]${NC}"
    read -r response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      error "Vault deployment aborted. Please deploy Consul first with 03-deploy-consul.sh."
    fi
    log "Continuing without Consul. Will use file storage backend."
  else
    log "Consul is available. You may consider using Consul as Vault storage backend."
    # We'll still default to file storage for simplicity in this script
  fi
  
  # Check for curl (needed for Vault verification)
  if ! command -v curl &> /dev/null; then
    warn "curl is not installed. This may be needed for Vault verification."
  fi
  
  # Check port availability for Vault
  if netstat -tuln | grep -q ":${VAULT_HTTP_PORT}[^0-9]"; then
    warn "Port ${VAULT_HTTP_PORT} is already in use by another process."
    echo -e "${YELLOW}Do you want to specify an alternative port for Vault? [y/N]${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      echo -e "${YELLOW}Please specify an alternative port for Vault HTTP:${NC}"
      read -r VAULT_HTTP_PORT
      log "Using alternative port for Vault: ${VAULT_HTTP_PORT}"
    else
      warn "Continuing with port ${VAULT_HTTP_PORT} despite conflict. This may cause issues."
    fi
  fi
  
  success "All prerequisites satisfied for Vault deployment"
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
    echo -e "${YELLOW}Please enter your Nomad management token (leave empty to skip auth):${NC}"
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

# Function to check Nomad connectivity with authentication
check_nomad_connectivity() {
  log "Checking Nomad connectivity..."
  
  # Set up Nomad environment
  if [ -n "${NOMAD_ADDR}" ]; then
    log "Using configured NOMAD_ADDR: ${NOMAD_ADDR}"
    export NOMAD_ADDR="${NOMAD_ADDR}"
  else
    # Try to guess a reasonable default
    export NOMAD_ADDR="http://127.0.0.1:4646"
    log "NOMAD_ADDR not set, using default: ${NOMAD_ADDR}"
  fi
  
  # Direct API check (doesn't require authentication for basic status)
  if curl -s -f "${NOMAD_ADDR}/v1/status/leader" &>/dev/null; then
    log "Nomad API is reachable at ${NOMAD_ADDR}"
  else
    warn "Cannot connect to Nomad API at ${NOMAD_ADDR}"
    warn "Please check if Nomad is running and accessible."
    return 1
  fi
  
  # Try authenticated operations (will need the token)
  if [ -n "${NOMAD_TOKEN}" ]; then
    if curl -s -f -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR}/v1/jobs" &>/dev/null; then
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

# Function to check Docker driver permissions (similar to Traefik utils)
check_docker_permissions() {
  log "Checking Docker driver permissions..."
  
  # Check if Docker is accessible
  if ! docker info &>/dev/null; then
    warn "Docker is not accessible by the current user"
    
    # Check if docker.sock has the right permissions
    local sock_perms=$(ls -la /var/run/docker.sock 2>/dev/null | awk '{print $1, $3, $4}' || echo "")
    log "Docker socket permissions: ${sock_perms}"
    
    # Check if nomad user is in docker group
    if ! getent group docker &>/dev/null || ! id nomad 2>/dev/null | grep -q docker; then
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
        
        log "Docker permissions fixed. You may need to restart Nomad for changes to take effect."
        echo -e "${YELLOW}Do you want to restart Nomad now? [y/N]${NC}"
        read -r restart_nomad
        
        if [[ "$restart_nomad" =~ ^([yY][eE][sS]|[yY])$ ]]; then
          # Try different restart methods based on the system
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