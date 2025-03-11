#!/bin/bash
# HomeLab DevOps Platform Installation Script
# Limited version executing only parts 01 and 02 for initial testing

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

# Main installation process
main() {
  echo_log "Starting HomeLab DevOps Platform installation (parts 01-02 only)..."
  
  # Setup script environment (creates log directory and loads config)
  setup_script_environment
  
  # Check prerequisites
  check_prerequisites
  
  # Load configuration (already done in setup_script_environment, but kept for clarity)
  load_configuration
  
  # Run module scripts 01 and 02 only
  run_module "01-setup-directories.sh"
  run_module "02-configure-volumes.sh"
  
  log "Initial installation (parts 01-02) completed successfully!"
  log "You can now proceed with testing before continuing to the next parts."
}

# Execute main function
main "$@"