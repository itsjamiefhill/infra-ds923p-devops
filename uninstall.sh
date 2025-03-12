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

# Function to stop Traefik job
stop_traefik() {
    log "Stopping Traefik job..."
    
    # Check if Traefik job exists in Nomad and stop it
    if nomad job status traefik &>/dev/null; then
        nomad job stop -purge traefik || warn "Failed to stop Traefik job"
        sleep 5 # Give Nomad time to stop the job
        success "Traefik job stopped and purged"
    else
        log "Traefik job not found or already stopped"
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
    stop_traefik
    
    # Step 1: Stop Consul job
    stop_consul
    
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