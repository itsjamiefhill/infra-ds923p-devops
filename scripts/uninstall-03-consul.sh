#!/bin/bash
# NOTE: Nomad token is provided by the main uninstall.sh script
# uninstall-03-consul.sh
# Uninstalls Consul deployed by 03-deploy-consul.sh

# Source the utilities script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/uninstall-utils.sh"

# Function to stop Consul service
stop_consul_service() {
  log "Stopping Consul service..."
  
  # Token is now provided directly by the main script
  # We don't need to load it from a file
  if [ -n "${NOMAD_TOKEN}" ]; then
    log "Using Nomad token provided by main script"
  else
    warn "No Nomad authentication token found."
    echo -e "${YELLOW}Please enter your Nomad management token (leave empty to skip Nomad operations):${NC}"
    read -r NOMAD_TOKEN
    if [ -n "${NOMAD_TOKEN}" ]; then
      export NOMAD_TOKEN
      log "Using provided Nomad token"
    else
      warn "No token provided. Will skip Nomad API operations."
    fi
  fi
  
  # Try to stop Consul job in Nomad if we have a token
  if check_nomad && [ -n "${NOMAD_TOKEN}" ]; then
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
    if check_nomad; then
      warn "Skipping Nomad API operations due to missing token."
    else
      warn "Skipping Nomad API operations as Nomad is not available."
    fi
  fi
  
  # Stop Consul using helper script if it exists
  if [ -f "${SCRIPT_DIR}/bin/stop-consul.sh" ] && [ -x "${SCRIPT_DIR}/bin/stop-consul.sh" ]; then
    log "Using stop-consul.sh script to stop Consul..."
    "${SCRIPT_DIR}/bin/stop-consul.sh" || warn "Failed to stop Consul using helper script"
  fi
  
  # Stop Docker containers if Docker is available
  if check_docker; then
    # Find and stop all Docker containers with "consul" in their name
    log "Stopping all Consul Docker containers..."
    consul_containers=$(sudo docker ps -a | grep -i consul | awk '{print $1}' || echo "")
    if [ -n "$consul_containers" ]; then
      for container in $consul_containers; do
        log "Stopping Docker container: $container"
        sudo docker stop "$container" && sudo docker rm "$container" || 
          warn "Failed to stop/remove container $container"
      done
      success "Consul containers stopped and removed"
    else
      log "No Consul containers found"
    fi
    
    # Ensure Consul doesn't restart by disabling auto-restart
    restart_containers=$(sudo docker ps -a --filter "restart=always" | grep -i consul | awk '{print $1}' || echo "")
    if [ -n "$restart_containers" ]; then
      for container in $restart_containers; do
        log "Updating restart policy for container: $container"
        sudo docker update --restart=no "$container" || warn "Failed to update restart policy"
      done
    fi
    
    # As last resort, manually remove any Docker container that might contain "consul"
    sudo docker ps -a | grep -i consul | awk '{print $1}' | xargs -r sudo docker rm -f
    
    # Verify Docker cleanup
    if sudo docker ps | grep -qi consul; then
      warn "Some Consul containers are still running. You may need to stop them manually."
    else
      log "No Consul containers running"
    fi
  else
    warn "Docker is not available or accessible. Skipping Docker container cleanup."
  fi
  
  # Kill any remaining consul processes
  log "Checking for lingering Consul processes..."
  consul_pids=$(ps aux | grep -i [c]onsul | awk '{print $2}' || echo "")
  if [ -n "$consul_pids" ]; then
    for pid in $consul_pids; do
      log "Killing process: $pid"
      sudo kill -9 "$pid" || warn "Failed to kill process $pid"
    done
  fi
}

# Function to remove Consul DNS integration
remove_consul_dns() {
  log "Removing Consul DNS integration..."
  
  # Remove from hosts file
  if check_sudo_available; then
    log "Checking /etc/hosts for Consul entries..."
    if grep -q "consul\.service\.consul" /etc/hosts; then
      log "Removing consul.service.consul entries from /etc/hosts..."
      sudo sed -i '/consul\.service\.consul/d' /etc/hosts || warn "Failed to remove consul.service.consul entry from /etc/hosts"
    fi
    
    if grep -q "consul\.service\." /etc/hosts; then
      log "Removing other consul service entries from /etc/hosts..."
      sudo sed -i '/consul\.service\./d' /etc/hosts || warn "Failed to remove consul service entries from /etc/hosts"
    fi
    
    # Remove the main Consul host entry from /etc/hosts if found
    if [[ -n "$DOMAIN" ]] && grep -q "consul\.${DOMAIN}" /etc/hosts; then
      log "Removing consul.${DOMAIN} entry from /etc/hosts..."
      sudo sed -i "/consul\.${DOMAIN}/d" /etc/hosts || warn "Failed to remove consul.${DOMAIN} entry from /etc/hosts"
    fi
    
    success "Consul DNS entries removed from hosts file"
  else
    warn "Cannot modify hosts file without sudo access"
  fi
  
  # Check and clean up dnsmasq configuration if it exists
  if [ -f "/etc/dnsmasq.conf" ]; then
    log "Checking for Consul entries in dnsmasq configuration..."
    if grep -q "server=/consul/" /etc/dnsmasq.conf; then
      if check_sudo_available; then
        log "Removing consul entries from /etc/dnsmasq.conf..."
        sudo sed -i '/server=\/consul\//d' /etc/dnsmasq.conf || warn "Failed to remove consul entries from dnsmasq.conf"
        
        # Restart dnsmasq if it's running
        if command -v systemctl &>/dev/null && systemctl is-active --quiet dnsmasq; then
          log "Restarting dnsmasq service..."
          sudo systemctl restart dnsmasq || warn "Failed to restart dnsmasq service"
        fi
        
        success "Consul dnsmasq configuration removed"
      else
        warn "Cannot modify dnsmasq configuration without sudo access"
      fi
    fi
  fi
  
  # Check and clean up dnsmasq.conf.d directory if it exists
  if [ -d "/etc/dnsmasq.conf.d" ]; then
    log "Checking for Consul configuration in dnsmasq.conf.d..."
    if check_sudo_available; then
      if [ -f "/etc/dnsmasq.conf.d/10-consul" ]; then
        log "Removing /etc/dnsmasq.conf.d/10-consul..."
        sudo rm -f "/etc/dnsmasq.conf.d/10-consul" || warn "Failed to remove /etc/dnsmasq.conf.d/10-consul"
        
        # Restart dnsmasq if it's running
        if command -v systemctl &>/dev/null && systemctl is-active --quiet dnsmasq; then
          log "Restarting dnsmasq service..."
          sudo systemctl restart dnsmasq || warn "Failed to restart dnsmasq service"
        fi
        
        success "Consul dnsmasq configuration file removed"
      fi
    else
      warn "Cannot remove dnsmasq configuration without sudo access"
    fi
  fi
}

# Function to remove Consul scripts
remove_consul_scripts() {
  log "Removing Consul helper scripts..."
  
  # Define the scripts to be removed
  CONSUL_SCRIPTS=(
    "start-consul.sh"
    "stop-consul.sh"
    "consul-status.sh"
    "consul-logs.sh"
    "consul-troubleshoot.sh"
    "consul-tokens.sh"  # Added ACL token management script
    "apply-consul-tokens.sh"  # Added ACL token application script
  )
  
  # Remove the scripts
  for script in "${CONSUL_SCRIPTS[@]}"; do
    if [ -f "${SCRIPT_DIR}/bin/${script}" ]; then
      log "Removing ${script}..."
      rm -f "${SCRIPT_DIR}/bin/${script}" || warn "Failed to remove ${script}"
    fi
  done
  
  success "Consul helper scripts removed"
}

# Function to clean up Consul configuration files
cleanup_consul_configs() {
  log "Cleaning up Consul configuration files..."
  
  # Clean up configuration files
  CONFIG_DIR=${CONFIG_DIR:-"${SCRIPT_DIR}/config"}
  CONSUL_CONFIG_DIR="${CONFIG_DIR}/consul"
  
  # Clean up the Consul configuration directory
  if [ -d "${CONSUL_CONFIG_DIR}" ]; then
    log "Removing Consul configuration directory: ${CONSUL_CONFIG_DIR}"
    sudo rm -rf "${CONSUL_CONFIG_DIR}" || warn "Failed to remove ${CONSUL_CONFIG_DIR}"
  fi
  
  # Clean up the main Consul configuration file if it exists
  if [ -f "${CONFIG_DIR}/consul.conf" ]; then
    log "Removing Consul configuration file: ${CONFIG_DIR}/consul.conf"
    rm -f "${CONFIG_DIR}/consul.conf" || warn "Failed to remove ${CONFIG_DIR}/consul.conf"
  fi
  
  # Clean up the Consul tokens configuration file if it exists
  if [ -f "${CONFIG_DIR}/consul_tokens.conf" ]; then
    log "Removing Consul tokens configuration file: ${CONFIG_DIR}/consul_tokens.conf"
    rm -f "${CONFIG_DIR}/consul_tokens.conf" || warn "Failed to remove ${CONFIG_DIR}/consul_tokens.conf"
  fi
  
  # Clean up ACL tokens file
  if [ -f "${CONFIG_DIR}/consul/acl_tokens.json" ]; then
    log "Removing Consul ACL tokens file: ${CONFIG_DIR}/consul/acl_tokens.json"
    sudo rm -f "${CONFIG_DIR}/consul/acl_tokens.json" || warn "Failed to remove ${CONFIG_DIR}/consul/acl_tokens.json"
  }
  
  # Clean up host entries backup if it exists
  if [ -f "${CONFIG_DIR}/hosts.backup" ]; then
    log "Removing hosts backup file: ${CONFIG_DIR}/hosts.backup"
    rm -f "${CONFIG_DIR}/hosts.backup" || warn "Failed to remove ${CONFIG_DIR}/hosts.backup"
  fi
  
  # Clean up dnsmasq configuration backup if it exists
  if [ -f "${CONFIG_DIR}/dnsmasq.conf.backup" ]; then
    log "Removing dnsmasq.conf backup: ${CONFIG_DIR}/dnsmasq.conf.backup"
    rm -f "${CONFIG_DIR}/dnsmasq.conf.backup" || warn "Failed to remove ${CONFIG_DIR}/dnsmasq.conf.backup"
  fi
  
  # Clean up dnsmasq configuration file backup if it exists
  if [ -f "${CONFIG_DIR}/10-consul" ]; then
    log "Removing dnsmasq Consul config backup: ${CONFIG_DIR}/10-consul"
    rm -f "${CONFIG_DIR}/10-consul" || warn "Failed to remove ${CONFIG_DIR}/10-consul"
  fi
  
  # Clean up SSL certificates if they exist
  if [ -d "${DATA_DIR}/certificates/consul" ]; then
    log "Removing Consul SSL certificates: ${DATA_DIR}/certificates/consul"
    sudo rm -rf "${DATA_DIR}/certificates/consul" || warn "Failed to remove ${DATA_DIR}/certificates/consul"
  fi
  
  # Clean up Consul data directory
  if [ -d "${DATA_DIR}/consul_data" ]; then
    log "Removing Consul data directory: ${DATA_DIR}/consul_data"
    sudo rm -rf "${DATA_DIR}/consul_data" || warn "Failed to remove ${DATA_DIR}/consul_data"
  fi
  
  # Remove consul.reference file from job directory
  if [ -n "${JOB_DIR}" ] && [ -f "${JOB_DIR}/consul.reference" ]; then
    log "Removing consul.reference from job directory: ${JOB_DIR}/consul.reference"
    rm -f "${JOB_DIR}/consul.reference" || warn "Failed to remove ${JOB_DIR}/consul.reference"
  fi
  
  success "Consul configuration files cleaned up"
}

# Function to clean up ACL-specific configuration
cleanup_consul_acl_config() {
  log "Cleaning up Consul ACL configuration..."
  
  # Clean up the ACL configuration file
  if [ -f "${CONFIG_DIR}/consul/acl.json" ]; then
    log "Removing ACL configuration file: ${CONFIG_DIR}/consul/acl.json"
    sudo rm -f "${CONFIG_DIR}/consul/acl.json" || warn "Failed to remove ${CONFIG_DIR}/consul/acl.json"
  fi
  
  # Clean up the tokens file
  if [ -f "${CONFIG_DIR}/consul/acl_tokens.json" ]; then
    log "Removing ACL tokens file: ${CONFIG_DIR}/consul/acl_tokens.json"
    sudo rm -f "${CONFIG_DIR}/consul/acl_tokens.json" || warn "Failed to remove ${CONFIG_DIR}/consul/acl_tokens.json"
  fi
  
  # Clean up any token application script
  if [ -f "${SCRIPT_DIR}/bin/apply-consul-tokens.sh" ]; then
    log "Removing token application script: ${SCRIPT_DIR}/bin/apply-consul-tokens.sh"
    rm -f "${SCRIPT_DIR}/bin/apply-consul-tokens.sh" || warn "Failed to remove ${SCRIPT_DIR}/bin/apply-consul-tokens.sh"
  fi
  
  # Clean up token management script
  if [ -f "${SCRIPT_DIR}/bin/consul-tokens.sh" ]; then
    log "Removing token management script: ${SCRIPT_DIR}/bin/consul-tokens.sh"
    rm -f "${SCRIPT_DIR}/bin/consul-tokens.sh" || warn "Failed to remove ${SCRIPT_DIR}/bin/consul-tokens.sh"
  fi
  
  success "Consul ACL configuration cleaned up"
}

# Main function
main() {
  echo -e "\n${GREEN}==========================================================${NC}"
  echo -e "${GREEN}           Uninstalling Part 03: Consul Service          ${NC}"
  echo -e "${GREEN}==========================================================${NC}"
  
  if confirm "This will uninstall Consul, remove all related configuration files, and stop services. Continue?"; then
    # Stop Consul service
    stop_consul_service
    
    # Remove Consul DNS integration
    remove_consul_dns
    
    # Remove Consul helper scripts
    remove_consul_scripts
    
    # Clean up Consul configuration files
    cleanup_consul_configs
    
    # Clean up ACL-specific configuration
    cleanup_consul_acl_config
    
    success "Consul uninstallation completed"
  else
    log "Consul uninstallation cancelled"
  fi
}

# Execute main function if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi