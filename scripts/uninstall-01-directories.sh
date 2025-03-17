#!/bin/bash
# uninstall-01-directories.sh
# Removes directories created by 01-setup-directories.sh

# Source the utilities script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/uninstall-utils.sh"

# Function to remove data directories
remove_data_directories() {
  log "Starting removal of data directories..."
  
  if [ ! -d "${DATA_DIR}" ]; then
    warn "Data directory ${DATA_DIR} does not exist. Nothing to remove."
    return 0
  fi
  
  if confirm "Do you want to remove all data directories? This will delete all persistent data."; then
    log "Removing data directories..."
    
    # List directories to remove
    DATA_DIRS=(
      "${DATA_DIR}/high_performance"
      "${DATA_DIR}/high_capacity"
      "${DATA_DIR}/standard"
      "${DATA_DIR}/consul_data"
      "${DATA_DIR}/vault_data"
      "${DATA_DIR}/registry_data"
      "${DATA_DIR}/prometheus_data"
      "${DATA_DIR}/grafana_data"
      "${DATA_DIR}/loki_data"
      "${DATA_DIR}/postgres_data"
      "${DATA_DIR}/keycloak_data"
      "${DATA_DIR}/homepage_data"
      "${DATA_DIR}/certificates"
    )
    
    if confirm "Are you ABSOLUTELY SURE you want to delete all data in ${DATA_DIR}?"; then
      for dir in "${DATA_DIRS[@]}"; do
        if [ -d "$dir" ]; then
          log "Removing directory: $dir"
          sudo rm -rf "$dir" || warn "Failed to remove directory: $dir"
        fi
      done
      success "Data directories removed"
    else
      warn "Data directory deletion cancelled"
      return 1
    fi
  else
    log "Skipping data directory removal"
    return 0
  fi
}

# Function to remove log directories
remove_log_directories() {
  log "Checking for log directories..."
  
  if [ -d "${LOG_DIR}/platform" ]; then
    if confirm "Do you want to remove platform log files?"; then
      rm -rf "${LOG_DIR}/platform" || warn "Failed to remove platform log directory"
      success "Platform log directory removed"
    else
      log "Skipping platform log directory removal"
    fi
  else
    log "Platform log directory not found or already removed"
  fi
}

# Function to remove backup directories if they exist
remove_backup_directories() {
  if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
    log "Checking backup directories..."
    
    BACKUP_DIRS=(
      "${BACKUP_DIR}/system"
      "${BACKUP_DIR}/services"
      "${BACKUP_DIR}/datasets"
    )
    
    if confirm "Do you want to remove backup directories? This will delete all backup data."; then
      for dir in "${BACKUP_DIRS[@]}"; do
        if [ -d "$dir" ]; then
          log "Removing backup directory: $dir"
          sudo rm -rf "$dir" || warn "Failed to remove backup directory: $dir"
        fi
      done
      success "Backup directories removed"
    else
      log "Skipping backup directory removal"
    fi
  else
    log "Backup directories not found or not configured"
  fi
}

# Main function
main() {
  echo -e "\n${GREEN}==========================================================${NC}"
  echo -e "${GREEN}        Uninstalling Part 01: Directory Structure        ${NC}"
  echo -e "${GREEN}==========================================================${NC}"
  
  if confirm "This will remove data directories created by the setup script. Continue?"; then
    # Remove data directories
    remove_data_directories
    
    # Remove log directories
    remove_log_directories
    
    # Remove backup directories
    remove_backup_directories
    
    success "Directory cleanup completed"
  else
    log "Directory cleanup cancelled"
  fi
}

# Execute main function if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi