#!/bin/bash
# uninstall-04-traefik.sh
# Uninstalls Traefik deployed by 04-deploy-traefik.sh

# Source the utilities script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/uninstall-utils.sh"

# Function to stop Traefik service
stop_traefik_service() {
  log "Stopping Traefik service..."
  
  # Load Nomad token if available
  if [ -f "${CONFIG_DIR}/nomad_auth.conf" ]; then
    source "${CONFIG_DIR}/nomad_auth.conf"
    export NOMAD_TOKEN
    log "Loaded Nomad authentication token"
  else
    if check_nomad; then
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
  fi
  
  # Try to stop Traefik job in Nomad if we have a token
  if check_nomad && [ -n "${NOMAD_TOKEN}" ]; then
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
    if check_nomad; then
      warn "Skipping Nomad API operations due to missing token."
    else
      warn "Skipping Nomad API operations as Nomad is not available."
    fi
  fi
  
  # Stop Traefik using helper script if it exists
  if [ -f "${SCRIPT_DIR}/bin/stop-traefik.sh" ] && [ -x "${SCRIPT_DIR}/bin/stop-traefik.sh" ]; then
    log "Using stop-traefik.sh script to stop Traefik..."
    "${SCRIPT_DIR}/bin/stop-traefik.sh" || warn "Failed to stop Traefik using helper script"
  fi
  
  # Stop Docker containers if Docker is available
  if check_docker; then
    # Find and stop all Docker containers with "traefik" in their name
    log "Stopping all Traefik Docker containers..."
    traefik_containers=$(sudo docker ps -a | grep -i traefik | awk '{print $1}' || echo "")
    if [ -n "$traefik_containers" ]; then
      for container in $traefik_containers; do
        log "Stopping Docker container: $container"
        sudo docker stop "$container" && sudo docker rm "$container" || 
          warn "Failed to stop/remove container $container"
      done
      success "Traefik containers stopped and removed"
    else
      log "No Traefik containers found"
    fi
    
    # Ensure Traefik doesn't restart by disabling auto-restart
    restart_containers=$(sudo docker ps -a --filter "restart=always" | grep -i traefik | awk '{print $1}' || echo "")
    if [ -n "$restart_containers" ]; then
      for container in $restart_containers; do
        log "Updating restart policy for container: $container"
        sudo docker update --restart=no "$container" || warn "Failed to update restart policy"
      done
    fi
    
    # As last resort, manually remove any Docker container that might contain "traefik"
    sudo docker ps -a | grep -i traefik | awk '{print $1}' | xargs -r sudo docker rm -f
    
    # Verify Docker cleanup
    if sudo docker ps | grep -qi traefik; then
      warn "Some Traefik containers are still running. You may need to stop them manually."
    else
      log "No Traefik containers running"
    fi
  else
    warn "Docker is not available or accessible. Skipping Docker container cleanup."
  fi
  
  # Kill any remaining traefik processes
  log "Checking for lingering Traefik processes..."
  traefik_pids=$(ps aux | grep -i [t]raefik | awk '{print $2}' || echo "")
  if [ -n "$traefik_pids" ]; then
    for pid in $traefik_pids; do
      log "Killing process: $pid"
      sudo kill -9 "$pid" || warn "Failed to kill process $pid"
    done
  fi
}

# Function to remove Traefik DNS configuration
remove_traefik_dns() {
  log "Removing Traefik hosts file entries..."
  
  # Determine domain and host from config
  DOMAIN=${DOMAIN:-"homelab.local"}
  TRAEFIK_HOST=${TRAEFIK_HOST:-"traefik.${DOMAIN}"}
  
  # Remove hosts file entry
  if grep -q "${TRAEFIK_HOST}" /etc/hosts; then
    if confirm "Do you want to remove the Traefik entry (${TRAEFIK_HOST}) from /etc/hosts?"; then
      sudo sed -i "/${TRAEFIK_HOST}/d" /etc/hosts || warn "Failed to remove ${TRAEFIK_HOST} entry"
      success "Traefik hosts file entry removed"
    else
      log "Keeping Traefik hosts file entry"
    fi
  else
    log "Traefik hosts file entry not found"
  fi
}

# Function to remove Traefik helper scripts
remove_traefik_scripts() {
  log "Removing Traefik helper scripts..."
  
  # List of Traefik scripts to remove
  SCRIPTS=(
    "start-traefik.sh"
    "stop-traefik.sh"
    "traefik-status.sh"
    "traefik-logs.sh"
    "traefik-troubleshoot.sh"
  )
  
  for script in "${SCRIPTS[@]}"; do
    if [ -f "${SCRIPT_DIR}/bin/${script}" ]; then
      rm -f "${SCRIPT_DIR}/bin/${script}" || warn "Failed to remove ${script}"
      log "Removed ${script}"
    fi
  done
  
  # Check if bin directory is empty and remove it if it is
  if [ -d "${SCRIPT_DIR}/bin" ] && [ -z "$(ls -A ${SCRIPT_DIR}/bin 2>/dev/null)" ]; then
    log "Bin directory is empty, removing it..."
    rmdir "${SCRIPT_DIR}/bin" || warn "Failed to remove bin directory"
  fi
}

# Function to clean up Traefik configuration files
cleanup_traefik_configs() {
  log "Cleaning up Traefik configuration files..."
  
  # Remove job files
  if [ -f "${JOB_DIR}/traefik.hcl" ]; then
    rm -f "${JOB_DIR}/traefik.hcl" || warn "Failed to remove traefik.hcl"
    log "Removed traefik.hcl"
  fi
  
  # Remove generated traefik config directory if it exists
  if [ -d "${CONFIG_DIR}/traefik" ]; then
    rm -rf "${CONFIG_DIR}/traefik" || warn "Failed to remove traefik config directory"
    log "Removed traefik config directory"
  fi
  
  # Optionally remove certificates
  if [ -f "${DATA_DIR}/certificates/wildcard.crt" ] || [ -f "${DATA_DIR}/certificates/wildcard.key" ]; then
    if confirm "Do you want to remove the wildcard certificates from the certificates directory?"; then
      rm -f "${DATA_DIR}/certificates/wildcard.crt" || warn "Failed to remove wildcard.crt"
      rm -f "${DATA_DIR}/certificates/wildcard.key" || warn "Failed to remove wildcard.key"
      log "Removed wildcard certificates"
    else
      log "Keeping wildcard certificates"
    fi
  fi
  
  # Remove Traefik utility scripts
  for i in {a..e}; do
    if [ -f "${SCRIPT_DIR}/04${i}-traefik-utils.sh" ]; then
      rm -f "${SCRIPT_DIR}/04${i}-traefik-utils.sh" || warn "Failed to remove 04${i}-traefik-utils.sh"
      log "Removed 04${i}-traefik-utils.sh"
    fi
  done
  
  # Remove main Traefik deployment script
  if [ -f "${SCRIPT_DIR}/04-deploy-traefik.sh" ]; then
    rm -f "${SCRIPT_DIR}/04-deploy-traefik.sh" || warn "Failed to remove 04-deploy-traefik.sh"
    log "Removed 04-deploy-traefik.sh"
  fi
}

# Main function
main() {
  echo -e "\n${GREEN}==========================================================${NC}"
  echo -e "${GREEN}           Uninstalling Part 04: Traefik Service          ${NC}"
  echo -e "${GREEN}==========================================================${NC}"
  
  if confirm "This will uninstall Traefik, remove all related configuration files, and stop services. Continue?"; then
    # Stop Traefik service
    stop_traefik_service
    
    # Remove Traefik DNS integration
    remove_traefik_dns
    
    # Remove Traefik helper scripts
    remove_traefik_scripts
    
    # Clean up Traefik configuration files
    cleanup_traefik_configs
    
    success "Traefik uninstallation completed"
  else
    log "Traefik uninstallation cancelled"
  fi
}

# Execute main function if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi