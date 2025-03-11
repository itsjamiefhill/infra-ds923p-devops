#!/bin/bash
# uninstall.sh
# Limited uninstall script that cleans up directories and volumes from parts 01 and 02

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
    echo "=== Uninstallation (parts 01-02) started at $(date) ===" > "${LOGS_DIR}/uninstall.log"
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
        "high_performance"
        "high_capacity"
        "standard"
        "consul_data"
        "vault_data"
        "registry_data"
        "prometheus_data"
        "grafana_data"
        "loki_data"
        "postgres_data"
        "keycloak_data"
        "homepage_data"
        "certificates"
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
        
        success "Local configuration files cleaned up"
    else
        log "Skipping local file cleanup"
    fi
}

# Function to display uninstallation summary
show_summary() {
    echo -e "\n${GREEN}==========================================================${NC}"
    echo -e "${GREEN}      HomeLab DevOps Platform Uninstallation (Parts 01-02)   ${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "\n${BLUE}Uninstallation completed with the following actions:${NC}\n"
    
    # Check what was removed
    if [ ! -f "${CONFIG_DIR}/volumes.hcl" ]; then
        echo -e "- ${YELLOW}Config Files:${NC} Volume configuration removed"
    else
        echo -e "- ${YELLOW}Config Files:${NC} Volume configuration preserved"
    fi
    
    # Check Nomad volumes
    REMAINING_VOLUMES=$(nomad volume list 2>/dev/null | grep -v "^ID\|^No\|No volumes" | wc -l)
    if [ "$REMAINING_VOLUMES" -eq 0 ]; then
        echo -e "- ${YELLOW}Volumes:${NC} All Nomad volumes removed"
    else
        echo -e "- ${YELLOW}Volumes:${NC} Some Nomad volumes still exist ($REMAINING_VOLUMES)"
    fi
    
    # Check data directories
    if [ ! -d "${DATA_DIR}/high_performance" ] && [ ! -d "${DATA_DIR}/high_capacity" ] && [ ! -d "${DATA_DIR}/standard" ]; then
        echo -e "- ${YELLOW}Data:${NC} Data directories removed"
    else
        echo -e "- ${YELLOW}Data:${NC} Data directories preserved"
    fi
    
    echo -e "\n${BLUE}Log file:${NC} ${LOGS_DIR}/uninstall.log"
    
    echo -e "\n${GREEN}==========================================================${NC}"
}

# Main function
main() {
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${GREEN}  HomeLab DevOps Platform Uninstallation Script (Parts 01-02) ${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    
    # Confirm before proceeding
    if ! confirm "This will uninstall the HomeLab DevOps Platform directories and volumes (Parts 01-02). Do you want to continue?"; then
        echo -e "\n${YELLOW}Uninstallation cancelled.${NC}"
        exit 0
    fi
    
    # Setup logging
    setup_logging
    
    # Check Nomad
    check_nomad
    
    # Step 1: Remove Nomad volumes
    remove_nomad_volumes
    
    # Step 2: Remove volume data (optional)
    remove_volume_data
    
    # Step 3: Clean up local files (optional)
    cleanup_local_files
    
    # Show summary
    show_summary
}

# Execute main function
main "$@"