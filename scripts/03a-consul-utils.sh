#!/bin/bash
# 03a-consul-utils.sh
# Core utility functions for Consul deployment (Docker-only version)

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

# Get the Synology's primary IP address - using the same function as in config
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

# Function to check Docker driver permissions
check_docker_permissions() {
  log "Checking Docker permissions..."
  
  # Check if Docker is accessible
  if ! docker info &>/dev/null; then
    warn "Docker is not accessible by the current user"
    
    # Check if docker.sock has the right permissions
    local sock_perms=$(ls -la /var/run/docker.sock 2>/dev/null | awk '{print $1, $3, $4}' || echo "")
    log "Docker socket permissions: ${sock_perms}"
    
    # Provide guidance on fixing permissions
    echo -e "${YELLOW}Docker is not accessible. Would you like to fix permissions automatically? [y/N]${NC}"
    read -r fix_perms
    
    if [[ "$fix_perms" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      log "Fixing Docker permissions..."
      
      # Attempt to fix docker.sock permissions
      sudo chown root:docker /var/run/docker.sock || warn "Failed to change docker.sock ownership"
      sudo chmod 660 /var/run/docker.sock || warn "Failed to change docker.sock permissions"
      
      log "Docker permissions fixed. Checking if now accessible..."
      
      # Test if Docker is now accessible
      if ! docker info &>/dev/null; then
        warn "Docker is still not accessible. You may need to add your user to the docker group."
        
        echo -e "${YELLOW}Would you like to add the current user to the docker group? [y/N]${NC}"
        read -r add_user
        
        if [[ "$add_user" =~ ^([yY][eE][sS]|[yY])$ ]]; then
          sudo usermod -aG docker $(whoami) || warn "Failed to add user to docker group"
          log "Added current user to docker group. You may need to log out and back in for changes to take effect."
          
          # Inform user about session restart
          echo -e "${YELLOW}Important: You'll need to log out and log back in for group changes to take effect.${NC}"
          echo -e "${YELLOW}After logging back in, run this script again.${NC}"
          
          # Ask if they want to continue anyway by trying sudo
          echo -e "${YELLOW}Would you like to continue using sudo for docker commands? [y/N]${NC}"
          read -r use_sudo
          
          if [[ "$use_sudo" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            log "Continuing with sudo for Docker commands..."
          else
            error "Cannot continue without Docker access. Please log out, log back in, and try again."
          fi
        else
          warn "Docker access problem not resolved. Continuing but expect issues with Docker commands."
        fi
      else
        success "Docker is now accessible!"
      fi
    else
      warn "Docker permission issues not fixed. Continuing but expect issues with Docker commands."
    fi
  else
    log "Docker is accessible - permissions are correctly configured"
  fi
}