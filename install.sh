#!/bin/bash
# HomeLab DevOps Platform Installation Script
# Updated version executing parts 01-04 with Consul ACL integration

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
CONFIG_DIR="${SCRIPT_DIR}/config"
LOGS_DIR="${SCRIPT_DIR}/logs"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display status messages (console only, before log file is available)
echo_log() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo_error() {
  echo -e "${RED}[ERROR]${NC} $1"
  exit 1
}

# Function to create directories needed for logging
setup_script_environment() {
  echo_log "Setting up script environment..."
  
  # Source default configuration to get correct LOG_DIR
  if [ -f "${CONFIG_DIR}/default.conf" ]; then
    source "${CONFIG_DIR}/default.conf"
    # If custom config exists, load it
    if [ -f "${CONFIG_DIR}/custom.conf" ]; then
      source "${CONFIG_DIR}/custom.conf"
    fi
  fi
  
  # Now LOGS_DIR should be set from config if available
  LOGS_DIR=${LOG_DIR:-"${SCRIPT_DIR}/logs"}
  
  # Create logs directory if it doesn't exist
  mkdir -p "${LOGS_DIR}"
  
  # Initialize log file
  echo "=== Installation started at $(date) ===" > "${LOGS_DIR}/install.log"
  
  # Make all scripts executable
  chmod +x ${SCRIPTS_DIR}/*.sh
  
  echo_success "Script environment set up. Logs will be written to ${LOGS_DIR}/install.log"
}

# Function to display status messages (with logging to file)
log() {
  echo -e "${BLUE}[INFO]${NC} $1"
  echo "[INFO] $1" >> "${LOGS_DIR}/install.log"
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
  echo "[SUCCESS] $1" >> "${LOGS_DIR}/install.log"
}

warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
  echo "[WARNING] $1" >> "${LOGS_DIR}/install.log"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
  echo "[ERROR] $1" >> "${LOGS_DIR}/install.log"
  exit 1
}

# Function to check prerequisites
check_prerequisites() {
  log "Checking prerequisites..."
  
  # Check if nomad is installed
  if ! command -v nomad &> /dev/null; then
    error "Nomad is not installed. Please install Nomad first."
  fi
  
  # Check if docker is installed
  if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install Docker first."
  fi
  
  # Check for sudo access
  if ! sudo -n true 2>/dev/null; then
    warn "This script requires sudo access for some operations."
    sudo -v || error "Failed to obtain sudo privileges."
  fi
  
  # Check for curl (needed for Consul verification)
  if ! command -v curl &> /dev/null; then
    error "curl is not installed. Please install curl first."
  fi
  
  # Check for jq (needed for ACL token management)
  if ! command -v jq &> /dev/null; then
    error "jq is not installed. Please install jq first. It's needed for ACL token management."
  fi
  
  # Check for dig (needed for Consul DNS testing)
  if ! command -v dig &> /dev/null; then
    warn "dig is not installed. This will be needed for Consul DNS verification."
    warn "Consider installing dnsutils package."
  fi
  
  success "All prerequisites satisfied"
}

# Function to load configuration
load_configuration() {
  log "Loading configuration..."
  
  # Configuration was already loaded in setup_script_environment
  
  # Also load consul tokens if available (for subsequent modules)
  if [ -f "${CONFIG_DIR}/consul_tokens.conf" ]; then
    log "Loading Consul ACL tokens for service integration..."
    source "${CONFIG_DIR}/consul_tokens.conf"
    
    # Export tokens as environment variables for subsequent scripts
    export CONSUL_BOOTSTRAP_TOKEN
    export CONSUL_NOMAD_TOKEN
    export CONSUL_TRAEFIK_TOKEN
    export CONSUL_VAULT_TOKEN
    
    success "Consul ACL tokens loaded"
  else
    log "No Consul ACL tokens configuration found. Will be created during Consul deployment."
  fi
  
  success "Configuration loaded"
}

# Function to run a module script
run_module() {
  local module_name="$1"
  local script_path="${SCRIPTS_DIR}/${module_name}"
  
  log "Running module: ${module_name}"
  
  if [ -f "${script_path}" ]; then
    # Pass all configuration to the script
    ${script_path} || error "Module ${module_name} failed"
    
    # If this was the Consul module, check if we have new token configuration
    if [[ "$module_name" == "03-deploy-consul.sh" ]] && [ -f "${CONFIG_DIR}/consul_tokens.conf" ]; then
      log "Consul tokens generated. Loading for subsequent modules..."
      source "${CONFIG_DIR}/consul_tokens.conf"
      
      # Export tokens as environment variables for subsequent scripts
      export CONSUL_BOOTSTRAP_TOKEN
      export CONSUL_NOMAD_TOKEN
      export CONSUL_TRAEFIK_TOKEN
      export CONSUL_VAULT_TOKEN
      
      # Also display Nomad token for manual configuration
      if [ ! -z "$CONSUL_NOMAD_TOKEN" ]; then
        echo ""
        echo "================================================================="
        echo "CONSUL TOKEN FOR NOMAD CONFIGURATION"
        echo "================================================================="
        echo "Add the following to your Nomad configuration file (nomad.hcl):"
        echo ""
        echo "consul {"
        echo "  token = \"${CONSUL_NOMAD_TOKEN}\""
        echo "}"
        echo ""
        echo "Then restart Nomad to apply the changes."
        echo "================================================================="
      fi
    fi
    
    success "Module ${module_name} completed"
  else
    error "Module script not found: ${script_path}"
  fi
}

setup_nomad_ssl() {
  log "Setting up Nomad SSL environment..."
  
  # Set up environment variables for Nomad SSL
  export NOMAD_ADDR=https://127.0.0.1:4646
  export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
  export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
  export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem
  
  # If NOMAD_TOKEN is set in config, use it
  if [ -f "${CONFIG_DIR}/nomad_auth.conf" ]; then
    source "${CONFIG_DIR}/nomad_auth.conf"
  fi
  
  # Check if certificate files exist
  if [ ! -f "$NOMAD_CACERT" ] || [ ! -f "$NOMAD_CLIENT_CERT" ] || [ ! -f "$NOMAD_CLIENT_KEY" ]; then
    warn "Nomad SSL certificates not found at expected paths. SSL connections may fail."
  else
    success "Nomad SSL environment configured"
  fi
}

# Main installation process
main() {
  echo_log "Starting HomeLab DevOps Platform installation (parts 01-04)..."
  
  # Setup script environment (creates log directory and loads config)
  setup_script_environment
  
  # Set up SSL to secure nomad access
  setup_nomad_ssl

  # Check prerequisites
  check_prerequisites
  
  # Load configuration (already done in setup_script_environment, but kept for clarity)
  load_configuration
  
  # Run initial setup modules
  run_module "01-setup-directories.sh"
  run_module "02-configure-volumes.sh"
  
  # Deploy Consul with ACL
  run_module "03-deploy-consul.sh"
  
  # Check if we have Consul tokens and pause for Nomad configuration
  if [ -f "${CONFIG_DIR}/consul_tokens.conf" ]; then
    source "${CONFIG_DIR}/consul_tokens.conf"
    
    if [ ! -z "$CONSUL_NOMAD_TOKEN" ]; then
      echo ""
      echo "================================================================="
      echo "CONSUL TOKEN FOR NOMAD CONFIGURATION"
      echo "================================================================="
      echo "Consul has been deployed with ACL enabled."
      echo ""
      echo "Please add the following to your Nomad configuration file (nomad.hcl):"
      echo ""
      echo "consul {"
      echo "  token = \"${CONSUL_NOMAD_TOKEN}\""
      echo "}"
      echo ""
      echo "Then restart Nomad to apply the changes."
      echo "================================================================="
      
      # Pause for user action
      echo ""
      read -p "Press ENTER after you have updated and restarted Nomad to continue with Traefik deployment... " </dev/tty
      echo ""
      
      log "Continuing with deployment after Nomad configuration..."
    else
      warn "Consul token for Nomad was not generated properly. Check the Consul ACL setup."
    fi
  else
    warn "No Consul token configuration found. Proceeding without Nomad token setup."
  fi
  
  # Continue with Traefik deployment
  run_module "04-deploy-traefik.sh"
  
  log "Installation (parts 01-04) completed successfully!"
  log "You can access Consul UI at http://localhost:${CONSUL_HTTP_PORT} or http://consul.homelab.local (if DNS is configured)"
  log "You can access Traefik dashboard at https://${TRAEFIK_HOST:-traefik.homelab.local} or http://localhost:${TRAEFIK_ADMIN_PORT:-8081}" 
  log "You can now proceed with testing before continuing to the next parts."
  
  # Since we already paused for Nomad configuration, no need for a final reminder
  log "All components have been deployed with proper ACL configuration."
}

# Execute main function
main "$@"