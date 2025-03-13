#!/bin/bash
# scripts/uninstall-vault.sh
# Script to uninstall Vault components from the HomeLab DevOps Platform

# Script directory and parent directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_DIR="${PARENT_DIR}/config"
LOG_DIR="${PARENT_DIR}/logs"
JOB_DIR="${PARENT_DIR}/jobs"

# Source config files
if [ -f "${CONFIG_DIR}/default.conf" ]; then
    source "${CONFIG_DIR}/default.conf"
    # If custom config exists, load it
    if [ -f "${CONFIG_DIR}/custom.conf" ]; then
        source "${CONFIG_DIR}/custom.conf"
    fi
else
    echo "Configuration not found. Using default values."
    DATA_DIR=${DATA_DIR:-"/volume1/docker/nomad/volumes"}
    CONFIG_DIR=${CONFIG_DIR:-"/volume1/docker/nomad/config"}
    JOB_DIR=${JOB_DIR:-"/volume1/docker/nomad/jobs"}
    LOG_DIR=${LOG_DIR:-"/volume1/logs"}
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
  echo "[INFO] $1" >> "${LOG_DIR}/uninstall.log"
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
  echo "[SUCCESS] $1" >> "${LOG_DIR}/uninstall.log"
}

warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
  echo "[WARNING] $1" >> "${LOG_DIR}/uninstall.log"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
  echo "[ERROR] $1" >> "${LOG_DIR}/uninstall.log"
  exit 1
}

# Function to ask for confirmation
confirm() {
    echo -e "${YELLOW}"
    read -p "$1 [y/N] " -n 1 -r
    echo -e "${NC}"
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    return 0
}

# Function to fully stop all Vault-related jobs and containers
stop_vault() {
  log "Performing comprehensive Vault shutdown..."
    
  # Load Nomad token if available
  if [ -f "${PARENT_DIR}/config/nomad_auth.conf" ]; then
    source "${PARENT_DIR}/config/nomad_auth.conf"
    export NOMAD_TOKEN
    log "Loaded Nomad authentication token"
  else
    warn "No Nomad authentication token found. You may need to provide one."
    echo -e "${YELLOW}Please enter your Nomad management token (leave empty to skip Nomad operations):${NC}"
    read -r NOMAD_TOKEN
    if [ -n "${NOMAD_TOKEN}" ]; then
      export NOMAD_TOKEN
      log "Using provided Nomad token"
    else
      warn "No token provided. Will skip Nomad API operations."
    fi
  fi
  
  # 1. Try to stop Vault job in Nomad if we have a token
  if [ -n "${NOMAD_TOKEN}" ]; then
    log "Checking for Vault job in Nomad..."
    
    # Test the token first
    if curl -s -f -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR:-http://127.0.0.1:4646}/v1/jobs" &>/dev/null; then
      log "Successfully authenticated with Nomad API"
      
      # Stop the Vault job if it exists
      job_exists=$(curl -s -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR:-http://127.0.0.1:4646}/v1/job/vault" | grep -v "job not found" || echo "")
      if [ -n "$job_exists" ]; then
        log "Found Vault job, stopping with API..."
        curl -s -X DELETE -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR:-http://127.0.0.1:4646}/v1/job/vault?purge=true"
        log "Vault job purged via API"
        sleep 5
      else
        log "Vault job not found in Nomad"
      fi
    else
      warn "Authentication with Nomad API failed. Token may be invalid."
      warn "Will proceed to docker container cleanup only."
    fi
  else
    warn "Skipping Nomad API operations due to missing token."
  fi
  
  # 2. Find and stop all Docker containers with "vault" in their name
  log "Stopping all Vault Docker containers..."
  vault_containers=$(sudo docker ps -a | grep -i vault | awk '{print $1}')
  if [ -n "$vault_containers" ]; then
    for container in $vault_containers; do
      log "Stopping Docker container: $container"
      sudo docker stop "$container" && sudo docker rm "$container"
    done
    success "All Vault containers stopped and removed"
  else
    log "No Vault containers found"
  fi
  
  # 3. Kill any remaining vault processes
  log "Checking for lingering Vault processes..."
  vault_pids=$(ps aux | grep -i [v]ault | awk '{print $2}')
  if [ -n "$vault_pids" ]; then
    for pid in $vault_pids; do
      log "Killing process: $pid"
      sudo kill -9 "$pid" || warn "Failed to kill process $pid"
    done
  fi
  
  # 4. Verify Docker cleanup
  log "Verifying Docker cleanup..."
  if sudo docker ps | grep -qi vault; then
    warn "Some Vault containers are still running. You may need to stop them manually."
  else
    log "No Vault containers running"
  fi
  
  # 5. Ensure Vault doesn't restart by disabling auto-restart
  log "Checking for container restart policies..."
  restart_containers=$(sudo docker ps -a --filter "restart=always" | grep -i vault | awk '{print $1}')
  if [ -n "$restart_containers" ]; then
    for container in $restart_containers; do
      log "Updating restart policy for container: $container"
      sudo docker update --restart=no "$container" || warn "Failed to update restart policy"
    done
  fi
  
  # 6. As last resort, manually remove any Docker container that might contain "vault"
  log "Forcing removal of any remaining Vault containers..."
  sudo docker ps -a | grep -i vault | awk '{print $1}' | xargs -r sudo docker rm -f
  
  success "Vault shutdown completed"
}

# Function to remove Vault bin scripts
remove_vault_scripts() {
  log "Removing Vault helper scripts..."
  
  # List of Vault scripts to remove
  SCRIPTS=(
    "start-vault.sh"
    "stop-vault.sh"
    "vault-status.sh"
    "vault-init.sh"
    "vault-unseal.sh"
    "vault-troubleshoot.sh"
    "vault-docker-run.sh"
    "vault-docker-stop.sh"
  )
  
  for script in "${SCRIPTS[@]}"; do
    if [ -f "${PARENT_DIR}/bin/${script}" ]; then
      rm -f "${PARENT_DIR}/bin/${script}" || warn "Failed to remove ${script}"
      log "Removed ${script}"
    fi
  done
  
  success "Vault helper scripts removed"
}

# Function to clean up Vault config files
cleanup_vault_configs() {
  log "Cleaning up Vault configuration files..."
  
  # Remove job files
  if [ -f "${JOB_DIR}/vault.hcl" ]; then
    rm -f "${JOB_DIR}/vault.hcl" || warn "Failed to remove vault.hcl"
    log "Removed vault.hcl"
  fi
  
  # Remove Vault configuration directory
  if [ -d "${CONFIG_DIR}/vault" ]; then
    if confirm "Do you want to remove the Vault configuration directory including initialization keys?"; then
      rm -rf "${CONFIG_DIR}/vault" || warn "Failed to remove Vault config directory"
      log "Removed Vault config directory"
    else
      log "Keeping Vault config directory"
    fi
  fi
  
  # Remove utility scripts if they exist
  for i in {a..e}; do
    if [ -f "${SCRIPT_DIR}/05${i}-vault-utils.sh" ]; then
      rm -f "${SCRIPT_DIR}/05${i}-vault-utils.sh" || warn "Failed to remove 05${i}-vault-utils.sh"
      log "Removed 05${i}-vault-utils.sh"
    fi
  done
  
  success "Vault configuration files cleaned up"
}

# Function to remove Vault volume data
remove_vault_data() {
  log "Checking Vault data volume..."
  
  # Check if the vault_data volume exists in Nomad
  if nomad volume status vault_data &>/dev/null; then
    if confirm "Do you want to deregister the vault_data volume from Nomad?"; then
      log "Deregistering vault_data volume from Nomad..."
      nomad volume delete vault_data || warn "Failed to delete vault_data volume"
      success "vault_data volume deregistered from Nomad"
    else
      log "Keeping vault_data volume registration in Nomad"
    fi
  else
    log "vault_data volume not found in Nomad"
  fi
  
  # Check if the vault data directory exists
  if [ -d "${DATA_DIR}/vault_data" ]; then
    if confirm "Do you want to remove the Vault data directory? This will delete all secrets and cannot be undone!"; then
      log "Removing Vault data directory..."
      sudo rm -rf "${DATA_DIR}/vault_data" || warn "Failed to remove Vault data directory"
      success "Vault data directory removed"
    else
      log "Keeping Vault data directory"
    fi
  else
    log "Vault data directory not found"
  fi
}

# Main uninstall Vault function
uninstall_vault() {
  echo -e "\n${GREEN}==========================================================${NC}"
  echo -e "${GREEN}              Uninstalling Vault Components             ${NC}"
  echo -e "${GREEN}==========================================================${NC}"
  
  # Confirm before proceeding
  if confirm "This will uninstall Vault, remove all related configuration files, and purge Nomad jobs. Continue?"; then
    # Stop Vault completely
    stop_vault
    
    # Remove Vault helper scripts
    remove_vault_scripts
    
    # Clean up Vault configuration files
    cleanup_vault_configs
    
    # Remove Vault data
    remove_vault_data
    
    success "Vault uninstallation completed"
  else
    log "Vault uninstallation cancelled"
    return 1
  fi
  
  return 0
}

# Show summary of Vault uninstallation
show_vault_summary() {
  echo -e "\n${BLUE}Vault Uninstallation Summary:${NC}\n"
  
  # Check if Vault job exists
  if nomad job status vault &>/dev/null; then
    echo -e "- ${YELLOW}Vault Service:${NC} Still running as Nomad job"
  else
    echo -e "- ${YELLOW}Vault Service:${NC} Stopped and removed"
  fi
  
  # Check if Vault container exists
  if sudo docker ps | grep -qi vault; then
    echo -e "- ${YELLOW}Vault Container:${NC} Still running"
  else
    echo -e "- ${YELLOW}Vault Container:${NC} Stopped and removed"
  fi
  
  # Check if vault_data volume exists
  if nomad volume status vault_data &>/dev/null; then
    echo -e "- ${YELLOW}Vault Volume:${NC} Still registered in Nomad"
  else
    echo -e "- ${YELLOW}Vault Volume:${NC} Deregistered from Nomad"
  fi
  
  # Check if Vault data directory exists
  if [ -d "${DATA_DIR}/vault_data" ]; then
    echo -e "- ${YELLOW}Vault Data:${NC} Directory still exists"
  else
    echo -e "- ${YELLOW}Vault Data:${NC} Directory removed"
  fi
  
  # Check if Vault helper scripts exist
  if [ -f "${PARENT_DIR}/bin/start-vault.sh" ] || [ -f "${PARENT_DIR}/bin/vault-init.sh" ]; then
    echo -e "- ${YELLOW}Helper Scripts:${NC} Some scripts still exist"
  else
    echo -e "- ${YELLOW}Helper Scripts:${NC} All removed"
  fi
  
  # Check if Vault configuration exists
  if [ -f "${JOB_DIR}/vault.hcl" ] || [ -d "${CONFIG_DIR}/vault" ]; then
    echo -e "- ${YELLOW}Configuration:${NC} Some configuration files still exist"
  else
    echo -e "- ${YELLOW}Configuration:${NC} All removed"
  fi
}

# Check if script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Create logs directory if it doesn't exist
  mkdir -p "${LOG_DIR}"
  echo "=== Vault uninstallation started at $(date) ===" >> "${LOG_DIR}/uninstall.log"
  
  # Run the uninstall function
  uninstall_vault
  
  # Show summary
  show_vault_summary
fi