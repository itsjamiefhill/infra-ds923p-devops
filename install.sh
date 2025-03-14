#!/bin/bash
# HomeLab DevOps Platform Installation Script
# Updated version executing parts 01-04 for initial testing

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
  
  # Run module scripts 01, 02, 03, and 04
  run_module "01-setup-directories.sh"
  run_module "02-configure-volumes.sh"
  run_module "03-deploy-consul.sh"
  run_module "04-deploy-traefik.sh"
  
  log "Installation (parts 01-04) completed successfully!"
  log "You can access Consul UI at http://localhost:${CONSUL_HTTP_PORT} or http://consul.homelab.local (if DNS is configured)"
  log "You can access Traefik dashboard at https://${TRAEFIK_HOST:-traefik.homelab.local} or http://localhost:${TRAEFIK_ADMIN_PORT:-8081}" 
  log "You can now proceed with testing before continuing to the next parts."
}

# Execute main function
main "$@"