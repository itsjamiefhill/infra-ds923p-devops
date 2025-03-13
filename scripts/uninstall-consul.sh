#!/bin/bash
# scripts/uninstall-consul.sh
# Script to uninstall Consul components from the HomeLab DevOps Platform

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

# Function to remove Consul DNS configuration
remove_consul_dns() {
    log "Removing Consul DNS integration..."
    
    # Remove hosts file entry
    if grep -q "consul\.service\.consul" /etc/hosts; then
        if confirm "Do you want to remove the Consul entry from /etc/hosts?"; then
            sudo sed -i '/consul\.service\.consul/d' /etc/hosts
            success "Consul hosts file entry removed"
        else
            log "Keeping Consul hosts file entry"
        fi
    else
        log "Consul hosts file entry not found"
    fi
    
    # Try to remove dnsmasq configuration if it exists
    if [ -f "/etc/dnsmasq.conf.d/10-consul" ]; then
        if confirm "Do you want to remove Consul dnsmasq integration?"; then
            sudo rm -f /etc/dnsmasq.conf.d/10-consul
            # Try to restart dnsmasq if it exists
            if command -v systemctl &>/dev/null && systemctl list-unit-files | grep -q dnsmasq; then
                sudo systemctl restart dnsmasq || warn "Failed to restart dnsmasq service"
            fi
            success "Consul dnsmasq integration removed"
        else
            log "Keeping Consul dnsmasq integration"
        fi
    else
        log "Consul dnsmasq integration not found"
    fi
    
    # Check if there's a DNS backup config
    if [ -f "${CONFIG_DIR}/10-consul" ]; then
        rm -f "${CONFIG_DIR}/10-consul" || warn "Failed to remove 10-consul backup config"
        log "Removed 10-consul backup config"
    fi
}

# Function to fully stop all Consul-related jobs and containers
stop_consul() {
  log "Performing comprehensive Consul shutdown..."
    
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
  
  # 1. Try to stop Consul job in Nomad if we have a token
  if [ -n "${NOMAD_TOKEN}" ]; then
    log "Checking for Consul job in Nomad..."
    
    # Test the token first
    if curl -s -f -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR:-http://127.0.0.1:4646}/v1/jobs" &>/dev/null; then
      log "Successfully authenticated with Nomad API"
      
      # Stop the Consul job if it exists
      job_exists=$(curl -s -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR:-http://127.0.0.1:4646}/v1/job/consul" | grep -v "job not found" || echo "")
      if [ -n "$job_exists" ]; then
        log "Found Consul job, stopping with API..."
        curl -s -X DELETE -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR:-http://127.0.0.1:4646}/v1/job/consul?purge=true"
        log "Consul job purged via API"
        sleep 5
      else
        log "Consul job not found in Nomad"
      fi
    else
      warn "Authentication with Nomad API failed. Token may be invalid."
      warn "Will proceed to docker container cleanup only."
    fi
  else
    warn "Skipping Nomad API operations due to missing token."
  fi
  
  # 2. Find and stop all Docker containers with "consul" in their name
  log "Stopping all Consul Docker containers..."
  consul_containers=$(sudo docker ps -a | grep -i consul | awk '{print $1}')
  if [ -n "$consul_containers" ]; then
    for container in $consul_containers; do
      log "Stopping Docker container: $container"
      sudo docker stop "$container" && sudo docker rm "$container"
    done
    success "All Consul containers stopped and removed"
  else
    log "No Consul containers found"
  fi
  
  # 3. Kill any remaining consul processes
  log "Checking for lingering Consul processes..."
  consul_pids=$(ps aux | grep -i [c]onsul | awk '{print $2}')
  if [ -n "$consul_pids" ]; then
    for pid in $consul_pids; do
      log "Killing process: $pid"
      sudo kill -9 "$pid" || warn "Failed to kill process $pid"
    done
  fi
  
  # 4. Verify Docker cleanup
  log "Verifying Docker cleanup..."
  if sudo docker ps | grep -qi consul; then
    warn "Some Consul containers are still running. You may need to stop them manually."
  else
    log "No Consul containers running"
  fi
  
  # 5. Ensure Consul doesn't restart by disabling auto-restart
  log "Checking for container restart policies..."
  restart_containers=$(sudo docker ps -a --filter "restart=always" | grep -i consul | awk '{print $1}')
  if [ -n "$restart_containers" ]; then
    for container in $restart_containers; do
      log "Updating restart policy for container: $container"
      sudo docker update --restart=no "$container" || warn "Failed to update restart policy"
    done
  fi
  
  # 6. As last resort, manually remove any Docker container that might contain "consul"
  log "Forcing removal of any remaining Consul containers..."
  sudo docker ps -a | grep -i consul | awk '{print $1}' | xargs -r sudo docker rm -f
  
  success "Consul shutdown completed"
}

# Function to remove Consul bin scripts
remove_consul_scripts() {
  log "Removing Consul helper scripts..."
  
  # List of Consul scripts to remove
  SCRIPTS=(
    "start-consul.sh"
    "stop-consul.sh"
    "consul-status.sh"
    "consul-troubleshoot.sh"
    "consul-docker-run.sh"
    "consul-docker-stop.sh"
  )
  
  for script in "${SCRIPTS[@]}"; do
    if [ -f "${PARENT_DIR}/bin/${script}" ]; then
      rm -f "${PARENT_DIR}/bin/${script}" || warn "Failed to remove ${script}"
      log "Removed ${script}"
    fi
  done
  
  success "Consul helper scripts removed"
}

# Function to clean up Consul config files
cleanup_consul_configs() {
  log "Cleaning up Consul configuration files..."
  
  # Remove job files
  if [ -f "${JOB_DIR}/consul.hcl" ]; then
    rm -f "${JOB_DIR}/consul.hcl" || warn "Failed to remove consul.hcl"
    log "Removed consul.hcl"
  fi
  
  if [ -f "${JOB_DIR}/consul.reference" ]; then
    rm -f "${JOB_DIR}/consul.reference" || warn "Failed to remove consul.reference"
    log "Removed consul.reference"
  fi
  
  # Remove Consul configuration directory if it exists
  if [ -d "${CONFIG_DIR}/consul" ]; then
    rm -rf "${CONFIG_DIR}/consul" || warn "Failed to remove consul config directory"
    log "Removed consul config directory"
  fi
  
  # Remove utility scripts if they exist
  for i in {a..d}; do
    if [ -f "${SCRIPT_DIR}/03${i}-consul-utils.sh" ]; then
      rm -f "${SCRIPT_DIR}/03${i}-consul-utils.sh" || warn "Failed to remove 03${i}-consul-utils.sh"
      log "Removed 03${i}-consul-utils.sh"
    fi
  done
  
  success "Consul configuration files cleaned up"
}

# Function to remove Consul data
remove_consul_data() {
  log "Checking Consul data volume..."
  
  # Check if the consul_data volume exists in Nomad
  if nomad volume status consul_data &>/dev/null; then
    if confirm "Do you want to deregister the consul_data volume from Nomad?"; then
      log "Deregistering consul_data volume from Nomad..."
      nomad volume delete consul_data || warn "Failed to delete consul_data volume"
      success "consul_data volume deregistered from Nomad"
    else
      log "Keeping consul_data volume registration in Nomad"
    fi
  else
    log "consul_data volume not found in Nomad"
  fi
  
  # Check if the consul data directory exists
  if [ -d "${DATA_DIR}/consul_data" ]; then
    if confirm "Do you want to remove the Consul data directory?"; then
      log "Removing Consul data directory..."
      sudo rm -rf "${DATA_DIR}/consul_data" || warn "Failed to remove Consul data directory"
      success "Consul data directory removed"
    else
      log "Keeping Consul data directory"
    fi
  else
    log "Consul data directory not found"
  fi
}

# Main uninstall Consul function
uninstall_consul() {
  echo -e "\n${GREEN}==========================================================${NC}"
  echo -e "${GREEN}              Uninstalling Consul Components             ${NC}"
  echo -e "${GREEN}==========================================================${NC}"
  
  # Confirm before proceeding
  if confirm "This will uninstall Consul, remove all related configuration files, and purge Nomad jobs. Continue?"; then
    # Stop Consul completely
    stop_consul
    
    # Remove Consul DNS integration
    remove_consul_dns
    
    # Remove Consul helper scripts
    remove_consul_scripts
    
    # Clean up Consul configuration files
    cleanup_consul_configs
    
    # Remove Consul data
    remove_consul_data
    
    success "Consul uninstallation completed"
  else
    log "Consul uninstallation cancelled"
    return 1
  fi
  
  return 0
}

# Show summary of Consul uninstallation
show_consul_summary() {
  echo -e "\n${BLUE}Consul Uninstallation Summary:${NC}\n"
  
  # Check if Consul job exists
  if nomad job status consul &>/dev/null; then
    echo -e "- ${YELLOW}Consul Service:${NC} Still running as Nomad job"
  else
    echo -e "- ${YELLOW}Consul Service:${NC} Stopped and removed"
  fi
  
  # Check if Consul container exists
  if sudo docker ps | grep -qi consul; then
    echo -e "- ${YELLOW}Consul Container:${NC} Still running"
  else
    echo -e "- ${YELLOW}Consul Container:${NC} Stopped and removed"
  fi
  
  # Check if consul_data volume exists
  if nomad volume status consul_data &>/dev/null; then
    echo -e "- ${YELLOW}Consul Volume:${NC} Still registered in Nomad"
  else
    echo -e "- ${YELLOW}Consul Volume:${NC} Deregistered from Nomad"
  fi
  
  # Check if Consul data directory exists
  if [ -d "${DATA_DIR}/consul_data" ]; then
    echo -e "- ${YELLOW}Consul Data:${NC} Directory still exists"
  else
    echo -e "- ${YELLOW}Consul Data:${NC} Directory removed"
  fi
  
  # Check if Consul helper scripts exist
  if [ -f "${PARENT_DIR}/bin/start-consul.sh" ] || [ -f "${PARENT_DIR}/bin/consul-status.sh" ]; then
    echo -e "- ${YELLOW}Helper Scripts:${NC} Some scripts still exist"
  else
    echo -e "- ${YELLOW}Helper Scripts:${NC} All removed"
  fi
  
  # Check if Consul DNS integration exists
  if grep -q "consul\.service\.consul" /etc/hosts || [ -f "/etc/dnsmasq.conf.d/10-consul" ]; then
    echo -e "- ${YELLOW}DNS:${NC} Some DNS integration still exists"
  else
    echo -e "- ${YELLOW}DNS:${NC} DNS integration removed"
  fi
  
  # Check if Consul configuration exists
  if [ -f "${JOB_DIR}/consul.hcl" ] || [ -d "${CONFIG_DIR}/consul" ]; then
    echo -e "- ${YELLOW}Configuration:${NC} Some configuration files still exist"
  else
    echo -e "- ${YELLOW}Configuration:${NC} All removed"
  fi
}

# Check if script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Create logs directory if it doesn't exist
  mkdir -p "${LOG_DIR}"
  echo "=== Consul uninstallation started at $(date) ===" >> "${LOG_DIR}/uninstall.log"
  
  # Run the uninstall function
  uninstall_consul
  
  # Show summary
  show_consul_summary
fi