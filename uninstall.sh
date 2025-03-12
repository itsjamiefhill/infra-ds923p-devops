#!/bin/bash
# uninstall.sh
# Uninstall script that cleans up directories, volumes, and services from parts 01-04

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
LOGS_DIR="${SCRIPT_DIR}/logs"

# Load configuration
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
  echo "[INFO] $1" >> "${LOGS_DIR}/uninstall.log"
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
  echo "[SUCCESS] $1" >> "${LOGS_DIR}/uninstall.log"
}

warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
  echo "[WARNING] $1" >> "${LOGS_DIR}/uninstall.log"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
  echo "[ERROR] $1" >> "${LOGS_DIR}/uninstall.log"
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

# Function to setup logging
setup_logging() {
    mkdir -p "${LOGS_DIR}"
    echo "=== Uninstallation (parts 01-04) started at $(date) ===" > "${LOGS_DIR}/uninstall.log"
}

# Function to check if Nomad is available
check_nomad() {
    log "Checking Nomad availability..."
    if ! nomad version > /dev/null 2>&1; then
        error "Nomad is not available. Make sure it's installed and in your PATH."
    fi
    success "Nomad is available"
}

# Function to stop Consul job
stop_consul() {
    log "Stopping Consul job..."
    
    # Check if Consul is running as a Docker container
    if sudo docker ps | grep -q "consul"; then
        log "Consul is running as a Docker container, stopping it..."
        sudo docker stop consul || warn "Failed to stop Consul container"
        sudo docker rm consul || warn "Failed to remove Consul container"
        success "Consul container stopped and removed"
    # Check if Consul job exists in Nomad and stop it
    elif nomad job status consul &>/dev/null; then
        nomad job stop -purge consul || warn "Failed to stop Consul job"
        sleep 5 # Give Nomad time to stop the job
        success "Consul job stopped and purged"
    else
        log "Consul job not found or already stopped"
    fi
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

# Function to remove Nomad volumes
remove_nomad_volumes() {
    log "Removing Nomad volumes..."
    
    # List of volumes to delete
    VOLUMES=(
        "consul_data"    # Consul data volume
        "certificates"   # SSL certificates volume
        "high_performance"
        "high_capacity"
        "standard"
        "vault_data"
        "registry_data"
        "prometheus_data"
        "grafana_data"
        "loki_data"
        "postgres_data"
        "keycloak_data"
        "homepage_data"
    )
    
    for volume in "${VOLUMES[@]}"; do
        log "Deleting volume ${volume}..."
        nomad volume delete ${volume} > /dev/null 2>&1 || warn "Failed to delete volume ${volume}, it may not exist or be in use"
    done
    
    success "Nomad volumes removed"
}

# Function to remove volume data
remove_volume_data() {
    if confirm "Do you want to remove all data directories? This will delete all persistent data."; then
        log "Removing data directories..."
        
        if [ -d "${DATA_DIR}" ]; then
            log "Removing data directory: ${DATA_DIR}"
            if confirm "Are you ABSOLUTELY SURE you want to delete all data in ${DATA_DIR}?"; then
                sudo rm -rf ${DATA_DIR}/* || warn "Failed to remove data directory contents"
                success "Data directories removed"
            else
                warn "Data directory deletion cancelled"
            fi
        else
            warn "Data directory ${DATA_DIR} not found"
        fi
    else
        log "Skipping data directory removal"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    if confirm "Do you want to remove generated configuration files?"; then
        log "Cleaning up local files..."
        
        # Remove volume configuration
        rm -f ${CONFIG_DIR}/volumes.hcl
        
        # Remove certificates volume configuration
        rm -f ${CONFIG_DIR}/certificates.hcl
        
        # Remove job files
        rm -f ${JOB_DIR}/consul.hcl
        rm -f ${JOB_DIR}/consul.reference
        rm -f ${JOB_DIR}/traefik.hcl
        
        # Remove Consul DNS backup config
        rm -f ${CONFIG_DIR}/10-consul
        
        # Remove start/stop scripts if they exist
        if [ -f "${SCRIPT_DIR}/bin/start-consul.sh" ]; then
            rm -f ${SCRIPT_DIR}/bin/start-consul.sh
            rm -f ${SCRIPT_DIR}/bin/stop-consul.sh
        fi
        
        # Remove Traefik start/stop scripts if they exist
        if [ -f "${SCRIPT_DIR}/bin/start-traefik.sh" ]; then
            rm -f ${SCRIPT_DIR}/bin/start-traefik.sh
            rm -f ${SCRIPT_DIR}/bin/stop-traefik.sh
        fi
        
        # Optionally remove certificates
        if confirm "Do you want to remove the wildcard certificates from the config directory?"; then
            rm -rf ${CONFIG_DIR}/certs || warn "Failed to remove certificates directory"
        fi
        
        success "Local configuration files cleaned up"
    else
        log "Skipping local file cleanup"
    fi
}

# Function to display uninstallation summary
show_summary() {
    echo -e "\n${GREEN}==========================================================${NC}"
    echo -e "${GREEN}      HomeLab DevOps Platform Uninstallation (Parts 01-04)   ${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "\n${BLUE}Uninstallation completed with the following actions:${NC}\n"
    
    # Check what was removed
    if [ ! -f "${CONFIG_DIR}/volumes.hcl" ]; then
        echo -e "- ${YELLOW}Config Files:${NC} Volume configuration removed"
    else
        echo -e "- ${YELLOW}Config Files:${NC} Volume configuration preserved"
    fi
    
    # Check if Consul job exists
    if sudo docker ps | grep -q "consul"; then
        echo -e "- ${YELLOW}Services:${NC} Consul service still running as Docker container"
    elif nomad job status consul &>/dev/null; then
        echo -e "- ${YELLOW}Services:${NC} Consul service still running as Nomad job"
    else
        echo -e "- ${YELLOW}Services:${NC} Consul service stopped and removed"
    fi
    
    # Check if Traefik job exists
    if nomad job status traefik &>/dev/null; then
        echo -e "- ${YELLOW}Services:${NC} Traefik service still running as Nomad job"
    else
        echo -e "- ${YELLOW}Services:${NC} Traefik service stopped and removed"
    fi
    
    # Check if hosts file has Consul entry
    if grep -q "consul\.service\.consul" /etc/hosts; then
        echo -e "- ${YELLOW}DNS:${NC} Consul hosts file entry preserved"
    else
        echo -e "- ${YELLOW}DNS:${NC} Consul hosts file entry removed"
    fi
    
    # Check if hosts file has Traefik entry
    if grep -q "traefik\.${DOMAIN:-homelab.local}" /etc/hosts; then
        echo -e "- ${YELLOW}DNS:${NC} Traefik hosts file entry preserved"
    else
        echo -e "- ${YELLOW}DNS:${NC} Traefik hosts file entry removed"
    fi
    
    # Check if Consul DNS integration exists
    if [ -f "/etc/dnsmasq.conf.d/10-consul" ]; then
        echo -e "- ${YELLOW}DNS:${NC} Consul dnsmasq integration preserved"
    else
        echo -e "- ${YELLOW}DNS:${NC} Consul dnsmasq integration removed"
    fi
    
    # Check Nomad volumes
    REMAINING_VOLUMES=$(nomad volume list 2>/dev/null | grep -v "^ID\|^No\|No volumes" | wc -l)
    if [ "$REMAINING_VOLUMES" -eq 0 ]; then
        echo -e "- ${YELLOW}Volumes:${NC} All Nomad volumes removed"
    else
        echo -e "- ${YELLOW}Volumes:${NC} Some Nomad volumes still exist ($REMAINING_VOLUMES)"
    fi
    
    # Check data directories
    if [ ! -d "${DATA_DIR}/consul_data" ] && [ ! -d "${DATA_DIR}/certificates" ] && [ ! -d "${DATA_DIR}/high_performance" ] && [ ! -d "${DATA_DIR}/high_capacity" ] && [ ! -d "${DATA_DIR}/standard" ]; then
        echo -e "- ${YELLOW}Data:${NC} Data directories removed"
    else
        echo -e "- ${YELLOW}Data:${NC} Data directories preserved"
    fi
    
    # Check certificates
    if [ ! -d "${CONFIG_DIR}/certs" ]; then
        echo -e "- ${YELLOW}Certificates:${NC} SSL certificates removed"
    else
        echo -e "- ${YELLOW}Certificates:${NC} SSL certificates preserved"
    fi
    
    echo -e "\n${BLUE}Log file:${NC} ${LOGS_DIR}/uninstall.log"
    
    echo -e "\n${GREEN}==========================================================${NC}"
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
  
  # Check if bin directory is empty and remove it if it is
  if [ -d "${PARENT_DIR}/bin" ] && [ -z "$(ls -A ${PARENT_DIR}/bin 2>/dev/null)" ]; then
    log "Bin directory is empty, removing it..."
    rmdir "${PARENT_DIR}/bin" || warn "Failed to remove bin directory"
  fi
  
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
  
  # Remove DNS integration
  if [ -f "${CONFIG_DIR}/10-consul" ]; then
    rm -f "${CONFIG_DIR}/10-consul" || warn "Failed to remove 10-consul"
    log "Removed 10-consul config backup"
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

# Function to uninstall Consul
uninstall_consul() {
  echo -e "\n${GREEN}==========================================================${NC}"
  echo -e "${GREEN}              Uninstalling Consul Components             ${NC}"
  echo -e "${GREEN}==========================================================${NC}"
  
  # Confirm before proceeding
  if confirm "This will uninstall Consul, remove all related configuration files, and purge Nomad jobs. Continue?"; then
    # Stop Consul completely
    stop_consul
    
    # Remove Consul helper scripts
    remove_consul_scripts
    
    # Clean up Consul configuration files
    cleanup_consul_configs
    
    success "Consul uninstallation completed"
  else
    log "Consul uninstallation cancelled"
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

# Main uninstall function
uninstall_traefik() {
    echo -e "\n${GREEN}==========================================================${NC}"
    echo -e "${GREEN}              Uninstalling Traefik Components             ${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    
    # Confirm before proceeding
    if confirm "This will uninstall Traefik, remove all related configuration files, and purge Nomad jobs. Continue?"; then
        # Stop Traefik job
        stop_traefik
        
        # Remove Traefik helper scripts
        remove_traefik_scripts
        
        # Clean up Traefik configuration files
        cleanup_traefik_configs
        
        # Optionally remove certificates
        if confirm "Do you want to remove the wildcard certificates from the certificates directory?"; then
            if [ -f "${DATA_DIR}/certificates/wildcard.crt" ]; then
                rm -f "${DATA_DIR}/certificates/wildcard.crt" || warn "Failed to remove wildcard.crt"
                log "Removed wildcard certificate"
            fi
            
            if [ -f "${DATA_DIR}/certificates/wildcard.key" ]; then
                rm -f "${DATA_DIR}/certificates/wildcard.key" || warn "Failed to remove wildcard.key"
                log "Removed wildcard key"
            fi
        else
            log "Keeping wildcard certificates"
        fi
        
        success "Traefik uninstallation completed"
    else
        log "Traefik uninstallation cancelled"
    fi
}

# Main function
main() {
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${GREEN}  HomeLab DevOps Platform Uninstallation Script (Parts 01-04) ${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    
    # Confirm before proceeding
    if ! confirm "This will uninstall the HomeLab DevOps Platform directories, volumes, and services (Parts 01-04). Do you want to continue?"; then
        echo -e "\n${YELLOW}Uninstallation cancelled.${NC}"
        exit 0
    fi
    
    # Setup logging
    setup_logging
    
    # Check Nomad
    check_nomad
    
    # Step 0: Stop Traefik job first (since it depends on Consul)
    uninstall_traefik

    # Step 1: Stop Consul job
    uninstall_consul

    if grep -q "consul\.${DOMAIN:-homelab.local}" /etc/hosts; then
        echo -e "- ${YELLOW}DNS:${NC} Consul hosts file entry preserved"
    else
        echo -e "- ${YELLOW}DNS:${NC} Consul hosts file entry removed"
    fi
    
    # Step 2: Remove Traefik DNS integration
    remove_traefik_dns
    
    # Step 3: Remove Consul DNS integration
    remove_consul_dns
    
    # Step 4: Remove Nomad volumes
    remove_nomad_volumes
    
    # Step 5: Remove volume data (optional)
    remove_volume_data
    
    # Step 6: Clean up local files (optional)
    cleanup_local_files
    
    # Show summary
    show_summary
}

# Execute main function
main "$@"