#!/bin/bash
# uninstall-02-volumes.sh
# Removes Nomad volumes created by 02-configure-volumes.sh

# Source the utilities script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/uninstall-utils.sh"

# Function to remove Nomad volumes
remove_nomad_volumes() {
  log "Removing Nomad volumes..."
  
  # Check if Nomad is available
  if ! check_nomad; then
    warn "Skipping volume removal as Nomad is not available"
    return 1
  fi
  
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
    log "Checking for volume ${volume}..."
    if nomad volume status ${volume} &>/dev/null; then
      log "Deleting volume ${volume}..."
      nomad volume delete ${volume} > /dev/null 2>&1 || 
        warn "Failed to delete volume ${volume}, it may be in use"
    else
      log "Volume ${volume} not found or already removed"
    fi
  done
  
  # Check if any volumes remain
  REMAINING_VOLUMES=$(nomad volume list 2>/dev/null | grep -v "^ID\|^No\|No volumes" | wc -l)
  if [ "$REMAINING_VOLUMES" -eq 0 ]; then
    success "All Nomad volumes removed"
  else
    warn "Some Nomad volumes still exist ($REMAINING_VOLUMES remaining)"
  fi
}

# Function to clean up volume configuration files
cleanup_volume_config() {
  log "Cleaning up volume configuration files..."
  
  # Remove volume configuration file
  if [ -f "${CONFIG_DIR}/volumes.hcl" ]; then
    rm -f "${CONFIG_DIR}/volumes.hcl" || warn "Failed to remove volumes.hcl"
    log "Removed volumes.hcl"
  else
    log "volumes.hcl not found or already removed"
  fi
  
  # Remove volume templates directory
  if [ -d "${CONFIG_DIR}/volume_templates" ]; then
    rm -rf "${CONFIG_DIR}/volume_templates" || warn "Failed to remove volume_templates directory"
    log "Removed volume_templates directory"
  else
    log "volume_templates directory not found or already removed"
  fi
  
  # Remove README file
  if [ -f "${CONFIG_DIR}/VOLUME_README.md" ]; then
    rm -f "${CONFIG_DIR}/VOLUME_README.md" || warn "Failed to remove VOLUME_README.md"
    log "Removed VOLUME_README.md"
  else
    log "VOLUME_README.md not found or already removed"
  fi
}

# Main function
main() {
  echo -e "\n${GREEN}==========================================================${NC}"
  echo -e "${GREEN}          Uninstalling Part 02: Nomad Volumes           ${NC}"
  echo -e "${GREEN}==========================================================${NC}"
  
  if confirm "This will remove Nomad volumes created by the setup script. Continue?"; then
    # Check if Nomad is available
    if check_nomad; then
      # Remove Nomad volumes
      remove_nomad_volumes
    else
      warn "Nomad is not available, skipping volume removal"
    fi
    
    # Clean up volume configuration files
    cleanup_volume_config
    
    success "Volume cleanup completed"
  else
    log "Volume cleanup cancelled"
  fi
}

# Execute main function if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi