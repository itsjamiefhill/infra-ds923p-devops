#!/bin/bash
# 01-setup-directories.sh
# Creates all required directories for the HomeLab DevOps Platform according to documentation

set -e

# Script directory and import common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PARENT_DIR}/logs"

source "${PARENT_DIR}/config/default.conf"

# If custom config exists, load it
if [ -f "${PARENT_DIR}/config/custom.conf" ]; then
    source "${PARENT_DIR}/config/custom.conf"
fi

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display status messages
log() {
  echo -e "${BLUE}[INFO]${NC} $1"
  echo "[INFO] $1" >> "${LOG_DIR}/install.log"
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
  echo "[SUCCESS] $1" >> "${LOG_DIR}/install.log"
}

warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
  echo "[WARNING] $1" >> "${LOG_DIR}/install.log"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
  echo "[ERROR] $1" >> "${LOG_DIR}/install.log"
  exit 1
}

# Create required directories according to the documentation
create_directories() {
  log "Creating directories based on documentation..."
  
  # Create config directory if it doesn't exist
  mkdir -p $CONFIG_DIR
  mkdir -p $JOB_DIR
  mkdir -p $LOG_DIR/platform
  
  # Create volume directories for storage classes
  sudo mkdir -p $DATA_DIR/high_performance
  sudo mkdir -p $DATA_DIR/high_capacity
  sudo mkdir -p $DATA_DIR/standard
  
  # Create service data directories
  sudo mkdir -p $DATA_DIR/consul_data
  sudo mkdir -p $DATA_DIR/vault_data
  sudo mkdir -p $DATA_DIR/registry_data
  sudo mkdir -p $DATA_DIR/prometheus_data
  sudo mkdir -p $DATA_DIR/grafana_data
  sudo mkdir -p $DATA_DIR/loki_data
  sudo mkdir -p $DATA_DIR/postgres_data
  sudo mkdir -p $DATA_DIR/keycloak_data
  sudo mkdir -p $DATA_DIR/homepage_data
  sudo mkdir -p $DATA_DIR/certificates
  
  # Create backup directories if specified
  if [ ! -z "$BACKUP_DIR" ]; then
    sudo mkdir -p $BACKUP_DIR/system
    sudo mkdir -p $BACKUP_DIR/services
    sudo mkdir -p $BACKUP_DIR/datasets
  fi
  
  # Set appropriate permissions
  sudo chmod -R 755 $DATA_DIR
  sudo chmod 777 $DATA_DIR/consul_data
  sudo chown -R 472:472 $DATA_DIR/grafana_data || warn "Could not set ownership for grafana_data"
  
  # Set specific permissions for other services if needed
  if [ -d "$DATA_DIR/postgres_data" ]; then
    sudo chown -R 999:999 $DATA_DIR/postgres_data || warn "Could not set ownership for postgres_data"
  fi
  
  success "Directories created according to documentation"
}

# Main function
main() {
  log "Starting directory setup according to documentation..."
  create_directories
  success "Directory setup completed"
}

# Execute main function
main "$@"