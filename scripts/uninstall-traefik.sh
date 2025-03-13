#!/bin/bash
# scripts/uninstall-traefik.sh
# Script to uninstall Traefik components from the HomeLab DevOps Platform

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

# Function to remove Traefik DNS configuration
remove_traefik_dns() {
    log "Removing Traefik hosts file entries..."
    
    # Determine domain from config
    DOMAIN=${DOMAIN:-"homelab.local"}
    TRAEFIK_HOST=${TRAEFIK_HOST:-"traefik.${DOMAIN}"}
    
    # Remove hosts file entry
    if grep -q "${TRAEFIK_HOST}" /etc/hosts; then
        if confirm "Do you want to remove the Traefik entry from /etc/hosts?"; then
            sudo sed -i "/${TRAEFIK_HOST}/d" /etc/hosts
            success "Traefik hosts file entry removed"
        else
            log "Keeping Traefik hosts file entry"
        fi
    else
        log "Traefik hosts file entry not found"
    fi
}

# Function to fully stop all Traefik-related jobs and containers
stop_traefik() {
    log "Performing comprehensive Traefik shutdown..."
    
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
    
    # 1. Try to stop Traefik job in Nomad if we have a token
    if [ -n "${NOMAD_TOKEN}" ]; then
        log "Checking for Traefik job in Nomad..."
        
        # Test the token first
        if curl -s -f -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR:-http://127.0.0.1:4646}/v1/jobs" &>/dev/null; then
            log "Successfully authenticated with Nomad API"
            
            # Stop the Traefik job if it exists
            job_exists=$(curl -s -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR:-http://127.0.0.1:4646}/v1/job/traefik" | grep -v "job not found" || echo "")
            if [ -n "$job_exists" ]; then
                log "Found Traefik job, stopping with API..."
                curl -s -X DELETE -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR:-http://127.0.0.1:4646}/v1/job/traefik?purge=true"
                log "Traefik job purged via API"
                sleep 5
            else
                log "Traefik job not found in Nomad"
            fi
            
            # Find all jobs with traefik in the name using the API
            log "Searching for any Traefik-related jobs..."
            all_jobs=$(curl -s -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR:-http://127.0.0.1:4646}/v1/jobs" | grep -o '"ID":"[^"]*"' | cut -d'"' -f4)
            for job in $all_jobs; do
                if echo "$job" | grep -qi traefik; then
                    log "Stopping job: $job"
                    curl -s -X DELETE -H "X-Nomad-Token: ${NOMAD_TOKEN}" "${NOMAD_ADDR:-http://127.0.0.1:4646}/v1/job/$job?purge=true"
                    log "Job $job purged via API"
                    sleep 2
                fi
            done
        else
            warn "Authentication with Nomad API failed. Token may be invalid."
            warn "Will proceed to docker container cleanup only."
        fi
    else
        warn "Skipping Nomad API operations due to missing token."
    fi
    
    # 2. Find and stop all Docker containers with "traefik" in their name
    log "Stopping all Traefik Docker containers..."
    traefik_containers=$(sudo docker ps -a | grep -i traefik | awk '{print $1}')
    if [ -n "$traefik_containers" ]; then
        for container in $traefik_containers; do
            log "Stopping Docker container: $container"
            sudo docker stop "$container" && sudo docker rm "$container"
        done
        success "All Traefik containers stopped and removed"
    else
        log "No Traefik containers found"
    fi
    
    # 3. Kill any remaining traefik processes
    log "Checking for lingering Traefik processes..."
    traefik_pids=$(ps aux | grep -i [t]raefik | awk '{print $2}')
    if [ -n "$traefik_pids" ]; then
        for pid in $traefik_pids; do
            log "Killing process: $pid"
            sudo kill -9 "$pid" || warn "Failed to kill process $pid"
        done
    fi
    
    # 4. Verify Docker cleanup
    log "Verifying Docker cleanup..."
    if sudo docker ps | grep -qi traefik; then
        warn "Some Traefik containers are still running. You may need to stop them manually."
    else
        log "No Traefik containers running"
    fi
    
    # 5. Ensure Traefik doesn't restart by disabling auto-restart
    log "Checking for container restart policies..."
    restart_containers=$(sudo docker ps -a --filter "restart=always" | grep -i traefik | awk '{print $1}')
    if [ -n "$restart_containers" ]; then
        for container in $restart_containers; do
            log "Updating restart policy for container: $container"
            sudo docker update --restart=no "$container" || warn "Failed to update restart policy"
        done
    fi
    
    # 6. As last resort, manually remove any Docker container that might contain "traefik"
    log "Forcing removal of any remaining Traefik containers..."
    sudo docker ps -a | grep -i traefik | awk '{print $1}' | xargs -r sudo docker rm -f
    
    success "Traefik shutdown completed"
}

# Function to remove Traefik bin scripts
remove_traefik_scripts() {
    log "Removing Traefik helper scripts..."
    
    # List of Traefik scripts to remove
    SCRIPTS=(
        "start-traefik.sh"
        "stop-traefik.sh"
        "traefik-status.sh"
        "traefik-troubleshoot.sh"
        "traefik-docker-run.sh"
        "traefik-docker-stop.sh"
    )
    
    for script in "${SCRIPTS[@]}"; do
        if [ -f "${PARENT_DIR}/bin/${script}" ]; then
            rm -f "${PARENT_DIR}/bin/${script}" || warn "Failed to remove ${script}"
            log "Removed ${script}"
        fi
    done
    
    success "Traefik helper scripts removed"
}

# Function to clean up Traefik config files
cleanup_traefik_configs() {
    log "Cleaning up Traefik configuration files..."
    
    # Remove job files
    if [ -f "${JOB_DIR}/traefik.hcl" ]; then
        rm -f "${JOB_DIR}/traefik.hcl" || warn "Failed to remove traefik.hcl"
        log "Removed traefik.hcl"
    fi
    
    # Remove generated traefik config directory if it exists
    if [ -d "${PARENT_DIR}/config/traefik" ]; then
        rm -rf "${PARENT_DIR}/config/traefik" || warn "Failed to remove traefik config directory"
        log "Removed traefik config directory"
    fi
    
    # Remove utility scripts if they exist
    for i in {a..e}; do
        if [ -f "${SCRIPT_DIR}/04${i}-traefik-utils.sh" ]; then
            rm -f "${SCRIPT_DIR}/04${i}-traefik-utils.sh" || warn "Failed to remove 04${i}-traefik-utils.sh"
            log "Removed 04${i}-traefik-utils.sh"
        fi
    done
    
    success "Traefik configuration files cleaned up"
}

# Function to deal with certificates
cleanup_certificates() {
    log "Checking certificates..."
    
    # Optionally remove certificates from config directory
    if [ -d "${CONFIG_DIR}/certs" ]; then
        if confirm "Do you want to remove the wildcard certificates from the config directory?"; then
            rm -rf "${CONFIG_DIR}/certs" || warn "Failed to remove certificates directory from config"
            log "Removed certificates from config directory"
        else
            log "Keeping certificates in config directory"
        fi
    fi
    
    # Optionally remove certificates from the certificates volume
    if [ -d "${DATA_DIR}/certificates" ]; then
        if confirm "Do you want to remove the wildcard certificates from the certificates directory?"; then
            if [ -f "${DATA_DIR}/certificates/wildcard.crt" ]; then
                sudo rm -f "${DATA_DIR}/certificates/wildcard.crt" || warn "Failed to remove wildcard.crt"
                log "Removed wildcard certificate"
            fi
            
            if [ -f "${DATA_DIR}/certificates/wildcard.key" ]; then
                sudo rm -f "${DATA_DIR}/certificates/wildcard.key" || warn "Failed to remove wildcard.key"
                log "Removed wildcard key"
            fi
            
            # If directory is empty now, remove it
            if [ -z "$(ls -A ${DATA_DIR}/certificates 2>/dev/null)" ]; then
                sudo rmdir "${DATA_DIR}/certificates" || warn "Failed to remove empty certificates directory"
                log "Removed empty certificates directory"
            fi
        else
            log "Keeping wildcard certificates"
        fi
    fi
}

# Main uninstall Traefik function
uninstall_traefik() {
    echo -e "\n${GREEN}==========================================================${NC}"
    echo -e "${GREEN}              Uninstalling Traefik Components             ${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    
    # Confirm before proceeding
    if confirm "This will uninstall Traefik, remove all related configuration files, and purge Nomad jobs. Continue?"; then
        # Stop Traefik job
        stop_traefik
        
        # Remove Traefik DNS integration
        remove_traefik_dns
        
        # Remove Traefik helper scripts
        remove_traefik_scripts
        
        # Clean up Traefik configuration files
        cleanup_traefik_configs
        
        # Handle certificates
        cleanup_certificates
        
        success "Traefik uninstallation completed"
    else
        log "Traefik uninstallation cancelled"
        return 1
    fi
    
    return 0
}

# Show summary of Traefik uninstallation
show_traefik_summary() {
    echo -e "\n${BLUE}Traefik Uninstallation Summary:${NC}\n"
    
    # Check if Traefik job exists
    if nomad job status traefik &>/dev/null; then
        echo -e "- ${YELLOW}Traefik Service:${NC} Still running as Nomad job"
    else
        echo -e "- ${YELLOW}Traefik Service:${NC} Stopped and removed"
    fi
    
    # Check if Traefik container exists
    if sudo docker ps | grep -qi traefik; then
        echo -e "- ${YELLOW}Traefik Container:${NC} Still running"
    else
        echo -e "- ${YELLOW}Traefik Container:${NC} Stopped and removed"
    fi
    
    # Check if certificates directory exists
    if [ -d "${DATA_DIR}/certificates" ]; then
        echo -e "- ${YELLOW}Certificates:${NC} Directory still exists"
    else
        echo -e "- ${YELLOW}Certificates:${NC} Directory removed"
    fi
    
    # Check if Traefik helper scripts exist
    if [ -f "${PARENT_DIR}/bin/start-traefik.sh" ] || [ -f "${PARENT_DIR}/bin/traefik-status.sh" ]; then
        echo -e "- ${YELLOW}Helper Scripts:${NC} Some scripts still exist"
    else
        echo -e "- ${YELLOW}Helper Scripts:${NC} All removed"
    fi
    
    # Check if Traefik host entry exists
    DOMAIN=${DOMAIN:-"homelab.local"}
    TRAEFIK_HOST=${TRAEFIK_HOST:-"traefik.${DOMAIN}"}
    if grep -q "${TRAEFIK_HOST}" /etc/hosts; then
        echo -e "- ${YELLOW}DNS:${NC} Traefik hosts file entry still exists"
    else
        echo -e "- ${YELLOW}DNS:${NC} Traefik hosts file entry removed"
    fi
    
    # Check if Traefik configuration exists
    if [ -f "${JOB_DIR}/traefik.hcl" ] || [ -d "${CONFIG_DIR}/traefik" ]; then
        echo -e "- ${YELLOW}Configuration:${NC} Some configuration files still exist"
    else
        echo -e "- ${YELLOW}Configuration:${NC} All removed"
    fi
}

# Check if script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Create logs directory if it doesn't exist
  mkdir -p "${LOG_DIR}"
  echo "=== Traefik uninstallation started at $(date) ===" >> "${LOG_DIR}/uninstall.log"
  
  # Run the uninstall function
  uninstall_traefik
  
  # Show summary
  show_traefik_summary
fi