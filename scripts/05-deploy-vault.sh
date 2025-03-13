#!/bin/bash
# 05-deploy-vault.sh
# Main coordinator script for Vault deployment on Synology DS923+

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_DIR="${PARENT_DIR}/config"
LOG_DIR="${PARENT_DIR}/logs"
JOB_DIR="${PARENT_DIR}/jobs"
LOG_FILE="${LOG_DIR}/vault-deploy.log"

# Source default configuration
if [ -f "${CONFIG_DIR}/default.conf" ]; then
  source "${CONFIG_DIR}/default.conf"
  # If custom config exists, load it
  if [ -f "${CONFIG_DIR}/custom.conf" ]; then
    source "${CONFIG_DIR}/custom.conf"
  fi
fi

# Default values if not set in config
DATA_DIR=${DATA_DIR:-"/volume1/docker/nomad/volumes"}
VAULT_HTTP_PORT=${VAULT_HTTP_PORT:-8200}
VAULT_IMAGE=${VAULT_IMAGE:-"hashicorp/vault:latest"}
VAULT_HOST=${VAULT_HOST:-"vault.${DOMAIN:-homelab.local}"}
VAULT_DEV_MODE=${VAULT_DEV_MODE:-"false"}
VAULT_CPU=${VAULT_CPU:-500}
VAULT_MEMORY=${VAULT_MEMORY:-1024}
VAULT_DATA_DIR="${DATA_DIR}/vault_data"

# Source utility scripts
source "${SCRIPT_DIR}/05a-vault-utils-core.sh"
source "${SCRIPT_DIR}/05b-vault-utils-storage.sh"
source "${SCRIPT_DIR}/05c-vault-utils-config.sh"
source "${SCRIPT_DIR}/05d-vault-utils-deploy.sh"
source "${SCRIPT_DIR}/05e-vault-utils-helpers.sh"

# Function to setup script environment
setup_script_environment() {
  echo "Setting up script environment..."
  
  # Create logs directory if it doesn't exist
  mkdir -p "${LOG_DIR}"
  
  # Initialize log file
  echo "=== Vault deployment started at $(date) ===" > "${LOG_FILE}"
  
  # Make all vault utils scripts executable
  chmod +x "${SCRIPT_DIR}/05a-vault-utils-core.sh"
  chmod +x "${SCRIPT_DIR}/05b-vault-utils-storage.sh"
  chmod +x "${SCRIPT_DIR}/05c-vault-utils-config.sh"
  chmod +x "${SCRIPT_DIR}/05d-vault-utils-deploy.sh"
  chmod +x "${SCRIPT_DIR}/05e-vault-utils-helpers.sh"
  
  echo "Script environment set up. Logs will be written to ${LOG_FILE}"
  log "Script environment initialized"
}

# Main function
main() {
  echo "Starting Vault deployment for HomeLab DevOps Platform..."
  
  # Setup script environment
  setup_script_environment
  
  # Display deployment information
  log "Deploying Vault with the following configuration:"
  log "- Data Directory: ${DATA_DIR}"
  log "- Vault HTTP Port: ${VAULT_HTTP_PORT}"
  log "- Vault Image: ${VAULT_IMAGE}"
  log "- Vault Host: ${VAULT_HOST}"
  log "- Vault Dev Mode: ${VAULT_DEV_MODE}"
  
  # Check prerequisites
  check_prerequisites
  
  # Setup Nomad authentication
  setup_nomad_auth
  
  # Setup storage for Vault
  setup_vault_storage
  
  # Create Vault configuration
  create_vault_config
  
  # Deploy Vault to Nomad
  deploy_vault
  
  # Create helper scripts
  create_helper_scripts
  
  # Display access information
  show_access_info
  
  log "Vault deployment completed successfully!"
}

# Execute main function
main "$@"