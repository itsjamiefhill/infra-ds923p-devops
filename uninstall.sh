#!/bin/bash
# uninstall.sh
# Main uninstallation script that coordinates removal of all HomeLab DevOps Platform components

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
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
    echo "=== Uninstallation started at $(date) ===" > "${LOGS_DIR}/uninstall.log"
}

# Function to check if Nomad is available
check_nomad() {
    log "Checking Nomad availability..."
    if ! nomad version > /dev/null 2>&1; then
        error "Nomad is not available. Make sure it's installed and in your PATH."
    fi
    success "Nomad is available"
}

# Function to remove Nomad volumes
remove_nomad_volumes() {
    log "Removing Nomad volumes..."
    
    # List of volumes to delete
    VOLUMES=(
        "certificates"   # SSL certificates volume
        "high_performance"
        "high_capacity"
        "standard"
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
    
    success "Nomad volumes removed (except for service-specific volumes)"
}

# Function to remove volume data
remove_volume_data() {
    if confirm "Do you want to remove all data directories? This will delete all persistent data."; then
        log "Removing data directories..."
        
        if [ -d "${DATA_DIR}" ]; then
            log "Checking data directory: ${DATA_DIR}"
            
            # Get list of directories
            dirs=$(find "${DATA_DIR}" -mindepth 1 -maxdepth 1 -type d -not -path "*/consul_data" -not -path "*/vault_data" -not -path "*/certificates")
            
            if [ -n "$dirs" ]; then
                if confirm "Are you ABSOLUTELY SURE you want to delete all general data in ${DATA_DIR}? (This excludes consul_data, vault_data, and certificates which are handled separately)"; then
                    echo "$dirs" | while read -r dir; do
                        sudo rm -rf "$dir" || warn "Failed to remove directory: $dir"
                        log "Removed directory: $dir"
                    done
                    success "General data directories removed"
                else
                    warn "Data directory deletion cancelled"
                fi
            else
                log "No general data directories to remove"
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
        rm -f ${CONFIG_DIR}/volumes.hcl || warn "Failed to remove volumes.hcl"
        
        # Remove certificates volume configuration
        rm -f ${CONFIG_DIR}/certificates.hcl || warn "Failed to remove certificates.hcl"
        
        # Remove start/stop scripts bin directory if empty
        if [ -d "${SCRIPT_DIR}/bin" ] && [ -z "$(ls -A ${SCRIPT_DIR}/bin 2>/dev/null)" ]; then
            rmdir "${SCRIPT_DIR}/bin" || warn "Failed to remove bin directory"
            log "Removed empty bin directory"
        fi
        
        success "Local configuration files cleaned up"
    else
        log "Skipping local file cleanup"
    fi
}

# Function to display uninstallation summary
show_summary() {
    echo -e "\n${GREEN}==========================================================${NC}"
    echo -e "${GREEN}      HomeLab DevOps Platform Uninstallation Summary   ${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    
    echo -e "\n${BLUE}Components uninstalled:${NC}\n"
    
    # Vault
    if nomad job status vault &>/dev/null; then
        echo -e "- ${YELLOW}Vault:${NC} Still running"
    else
        echo -e "- ${YELLOW}Vault:${NC} Uninstalled"
    fi
    
    # Traefik
    if nomad job status traefik &>/dev/null; then
        echo -e "- ${YELLOW}Traefik:${NC} Still running"
    else
        echo -e "- ${YELLOW}Traefik:${NC} Uninstalled"
    fi
    
    # Consul
    if nomad job status consul &>/dev/null || sudo docker ps | grep -qi consul; then
        echo -e "- ${YELLOW}Consul:${NC} Still running"
    else
        echo -e "- ${YELLOW}Consul:${NC} Uninstalled"
    fi
    
    echo -e "\n${BLUE}Data retention:${NC}\n"
    
    # Check Vault data
    if [ -d "${DATA_DIR}/vault_data" ]; then
        echo -e "- ${YELLOW}Vault Data:${NC} Preserved"
    else
        echo -e "- ${YELLOW}Vault Data:${NC} Removed"
    fi
    
    # Check Consul data
    if [ -d "${DATA_DIR}/consul_data" ]; then
        echo -e "- ${YELLOW}Consul Data:${NC} Preserved"
    else
        echo -e "- ${YELLOW}Consul Data:${NC} Removed"
    fi
    
    # Check certificates
    if [ -d "${DATA_DIR}/certificates" ]; then
        echo -e "- ${YELLOW}Certificates:${NC} Preserved"
    else
        echo -e "- ${YELLOW}Certificates:${NC} Removed"
    fi
    
    echo -e "\n${BLUE}Volumes:${NC}\n"
    
    REMAINING_VOLUMES=$(nomad volume list 2>/dev/null | grep -v "^ID\|^No\|No volumes" | wc -l)
    if [ "$REMAINING_VOLUMES" -eq 0 ]; then
        echo -e "- ${YELLOW}Nomad Volumes:${NC} All volumes removed"
    else
        echo -e "- ${YELLOW}Nomad Volumes:${NC} Some volumes still exist ($REMAINING_VOLUMES)"
        nomad volume list 2>/dev/null | grep -v "^ID\|^No\|No volumes" || echo "  None"
    fi
    
    echo -e "\n${BLUE}Configuration:${NC}\n"
    
    if [ -f "${CONFIG_DIR}/volumes.hcl" ]; then
        echo -e "- ${YELLOW}Volume Config:${NC} Preserved"
    else
        echo -e "- ${YELLOW}Volume Config:${NC} Removed"
    fi
    
    echo -e "\n${BLUE}For complete cleanup, you may want to:${NC}\n"
    echo -e "- Manually remove any remaining data in ${DATA_DIR}"
    echo -e "- Manually clean up any remaining configurations in ${CONFIG_DIR}"
    echo -e "- Manually remove any remaining helper scripts in ${SCRIPT_DIR}/bin"
    echo -e "- Manually deregister any remaining Nomad volumes"
    
    echo -e "\n${GREEN}==========================================================${NC}"
}

# Main function
main() {
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${GREEN}  HomeLab DevOps Platform Uninstallation Script ${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    
    # Confirm before proceeding
    if ! confirm "This will uninstall the HomeLab DevOps Platform. Do you want to continue?"; then
        echo -e "\n${YELLOW}Uninstallation cancelled.${NC}"
        exit 0
    fi
    
    # Setup logging
    setup_logging
    
    # Check Nomad
    check_nomad
    
    # Determine which components to uninstall
    echo -e "\n${BLUE}Select which components to uninstall:${NC}"
    
    uninstall_vault=false
    uninstall_traefik=false
    uninstall_consul=false
    
    if confirm "Uninstall Vault?"; then
        uninstall_vault=true
    fi
    
    if confirm "Uninstall Traefik?"; then
        uninstall_traefik=true
    fi
    
    if confirm "Uninstall Consul?"; then
        uninstall_consul=true
    fi
    
    # Make sure the uninstall scripts are executable
    chmod +x "${SCRIPTS_DIR}/uninstall-vault.sh" 2>/dev/null || true
    chmod +x "${SCRIPTS_DIR}/uninstall-traefik.sh" 2>/dev/null || true
    chmod +x "${SCRIPTS_DIR}/uninstall-consul.sh" 2>/dev/null || true
    
    # Uninstall selected components in reverse order
    if [ "$uninstall_vault" = true ]; then
        log "Uninstalling Vault..."
        "${SCRIPTS_DIR}/uninstall-vault.sh"
    fi
    
    if [ "$uninstall_traefik" = true ]; then
        log "Uninstalling Traefik..."
        "${SCRIPTS_DIR}/uninstall-traefik.sh"
    fi
    
    if [ "$uninstall_consul" = true ]; then
        log "Uninstalling Consul..."
        "${SCRIPTS_DIR}/uninstall-consul.sh"
    fi
    
    # Remove remaining Nomad volumes
    if confirm "Do you want to remove other Nomad volumes?"; then
        remove_nomad_volumes
    fi
    
    # Remove remaining volume data
    remove_volume_data
    
    # Clean up remaining local files
    cleanup_local_files
    
    # Show summary
    show_summary
    
    log "Uninstallation completed. Check the log file for details: ${LOGS_DIR}/uninstall.log"
}

# Execute main function
main "$@"