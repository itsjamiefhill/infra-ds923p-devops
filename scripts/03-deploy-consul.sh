#!/bin/bash
# 03-deploy-consul.sh
# Deploys Consul service discovery directly as a Docker container (no Nomad)

set -e

# Script directory and import common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Load all utility scripts
if [ -f "${SCRIPT_DIR}/03a-consul-utils.sh" ]; then
    source "${SCRIPT_DIR}/03a-consul-utils.sh"
else
    echo "Error: Could not find 03a-consul-utils.sh"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/03b-consul-utils.sh" ]; then
    source "${SCRIPT_DIR}/03b-consul-utils.sh"
else
    echo "Error: Could not find 03b-consul-utils.sh"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/03c-consul-utils.sh" ]; then
    source "${SCRIPT_DIR}/03c-consul-utils.sh"
else
    echo "Error: Could not find 03c-consul-utils.sh"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/03d-consul-utils.sh" ]; then
    source "${SCRIPT_DIR}/03d-consul-utils.sh"
else
    echo "Error: Could not find 03d-consul-utils.sh"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/03e-consul-acl-utils.sh" ]; then
    source "${SCRIPT_DIR}/03e-consul-acl-utils.sh"
else
    echo "Error: Could not find 03e-consul-acl-utils.sh"
    exit 1
fi

# Clear previous configuration to avoid conflicts
unset CONSUL_VERSION CONSUL_HTTP_PORT CONSUL_DNS_PORT CONSUL_CPU CONSUL_MEMORY CONSUL_HOST
unset CONSUL_BIND_ADDR CONSUL_ADVERTISE_ADDR DNS_USE_HOSTS_FILE DNS_USE_DNSMASQ
unset CONSUL_ENABLE_SSL CONSUL_ENABLE_ACL

# Source configuration files
source "${PARENT_DIR}/config/default.conf"

# If custom config exists, load it
if [ -f "${PARENT_DIR}/config/custom.conf" ]; then
    source "${PARENT_DIR}/config/custom.conf"
fi

# Set up logging
LOGS_DIR=${LOG_DIR:-"${PARENT_DIR}/logs"}
LOG_FILE="${LOGS_DIR}/consul_deploy.log"

# Ensure logs directory exists
mkdir -p "${LOGS_DIR}"

# Set default values if not defined in config
# Note: These should ideally be defined in default.conf, but keeping them here for backward compatibility
CONSUL_VERSION=${CONSUL_VERSION:-"1.15.4"}
CONSUL_HTTP_PORT=${CONSUL_HTTP_PORT:-8500}
CONSUL_DNS_PORT=${CONSUL_DNS_PORT:-8600}
CONSUL_CPU=${CONSUL_CPU:-500}
CONSUL_MEMORY=${CONSUL_MEMORY:-512}
CONSUL_HOST=${CONSUL_HOST:-"consul.${DOMAIN}"}
CONSUL_BIND_ADDR=${CONSUL_BIND_ADDR:-"$(get_primary_ip)"}
CONSUL_ADVERTISE_ADDR=${CONSUL_ADVERTISE_ADDR:-"$(get_primary_ip)"}
DNS_USE_HOSTS_FILE=${DNS_USE_HOSTS_FILE:-true}
DNS_USE_DNSMASQ=${DNS_USE_DNSMASQ:-false}
CONSUL_ENABLE_SSL=${CONSUL_ENABLE_SSL:-false}
CONSUL_ENABLE_ACL=${CONSUL_ENABLE_ACL:-true} # Enable ACL by default

# Print loaded configuration for debugging
log "Loaded configuration:"
log "DATA_DIR=${DATA_DIR}"
log "CONFIG_DIR=${CONFIG_DIR}"
log "JOB_DIR=${JOB_DIR}"
log "DOMAIN=${DOMAIN}"
log "CONSUL_VERSION=${CONSUL_VERSION}"
log "CONSUL_HTTP_PORT=${CONSUL_HTTP_PORT}"
log "CONSUL_DNS_PORT=${CONSUL_DNS_PORT}"
log "CONSUL_HOST=${CONSUL_HOST}"
log "CONSUL_BIND_ADDR=${CONSUL_BIND_ADDR}"
log "CONSUL_ADVERTISE_ADDR=${CONSUL_ADVERTISE_ADDR}"
log "CONSUL_ENABLE_SSL=${CONSUL_ENABLE_SSL}"
log "CONSUL_ENABLE_ACL=${CONSUL_ENABLE_ACL}"

display_nomad_token_and_pause() {
  if [ "${CONSUL_ENABLE_ACL}" = "true" ] && [ -f "${PARENT_DIR}/config/consul_tokens.json" ]; then
    # Check if the file is readable
    if [ -r "${PARENT_DIR}/config/consul_tokens.json" ]; then
      # Check if jq is available
      if command -v jq &> /dev/null; then
        # Safely extract values with default if missing
        NOMAD_TOKEN=$(jq -r '.nomad_token // "token_generation_failed"' "${PARENT_DIR}/config/consul_tokens.json" 2>/dev/null || echo "token_generation_failed")
        
        # Display the Nomad token and pause
        echo ""
        echo "================================================================="
        echo "NOMAD TOKEN FOR MANUAL CONFIGURATION"
        echo "================================================================="
        echo "You'll need the following token to configure Nomad:"
        echo ""
        echo "NOMAD TOKEN: ${NOMAD_TOKEN}"
        echo ""
        echo "Please copy this token now as you'll need it to configure Nomad manually."
        echo "================================================================="
        echo ""
        
        # Prompt to continue
        read -p "Press Enter to continue after copying the Nomad token..." </dev/tty
      else
        warn "jq command not found. Cannot parse token information."
        echo ""
        echo "================================================================="
        echo "NOMAD TOKEN FOR MANUAL CONFIGURATION"
        echo "================================================================="
        echo "Token file exists but couldn't be parsed (jq not installed)."
        echo "The tokens are saved in: ${PARENT_DIR}/config/consul_tokens.json"
        echo "Please install jq and extract the nomad_token manually before continuing."
        echo "================================================================="
        
        # Prompt to continue
        read -p "Press Enter to continue after checking the token file..." </dev/tty
      fi
    else
      warn "Token file exists but is not readable: ${PARENT_DIR}/config/consul_tokens.json"
      echo ""
      echo "================================================================="
      echo "NOMAD TOKEN FOR MANUAL CONFIGURATION"
      echo "================================================================="
      echo "Token file exists but is not readable due to permissions."
      echo "Please check permissions on: ${PARENT_DIR}/config/consul_tokens.json"
      echo "================================================================="
      
      # Prompt to continue
      read -p "Press Enter to continue after checking the token file..." </dev/tty
    fi
  else
    if [ "${CONSUL_ENABLE_ACL}" = "true" ]; then
      warn "ACL enabled but no token file was generated. You'll need to manually create tokens."
      echo ""
      echo "================================================================="
      echo "NOMAD TOKEN FOR MANUAL CONFIGURATION"
      echo "================================================================="
      echo "No token file was found. You'll need to manually create a Nomad token."
      echo "Use ${PARENT_DIR}/bin/consul-tokens.sh create nomad"
      echo "================================================================="
      
      # Prompt to continue
      read -p "Press Enter to continue..." </dev/tty
    fi
  fi
}

# Main function
main() {
  log "Starting Consul deployment..."
  
  # Step 1: Check Docker permissions (we need this regardless)
  check_docker_permissions
  
  # Step 2: Prepare the data directory
  prepare_consul_directory
  
  # Step 3: Prepare SSL certificates for Consul if enabled
  if [ "${CONSUL_ENABLE_SSL}" = "true" ]; then
    prepare_consul_ssl
  fi
  
  # Step 4: Prepare ACL configuration if enabled
  if [ "${CONSUL_ENABLE_ACL}" = "true" ]; then
    clean_up_token_files
    prepare_consul_acl
  fi
  
  # Step 5: Create helper scripts
  create_docker_helper_scripts
  
  # Step 6: Deploy Consul using Docker
  deploy_consul_docker
  
  # Step 7: Setup Consul DNS integration
  setup_consul_dns
  
  # Step 8: Add Consul host entry to /etc/hosts in non-interactive mode
  SYNOLOGY_IP=$(get_primary_ip)
  
  if ! grep -q "${CONSUL_HOST}" /etc/hosts; then
    log "Adding Consul host entry to /etc/hosts in non-interactive mode..."
    echo "${SYNOLOGY_IP}  ${CONSUL_HOST}" | sudo tee -a /etc/hosts > /dev/null
    success "Hosts file updated automatically for ${CONSUL_HOST}"
  else
    log "Consul host entry already exists in hosts file"
  fi
  
  # Step 9: Bootstrap ACL system if enabled
  # Set to continue on error - we'll still create a default token file
  set +e
  if [ "${CONSUL_ENABLE_ACL}" = "true" ]; then
    bootstrap_consul_acl || {
      warn "ACL bootstrapping encountered issues. Creating a default token file."
      
      # Create a default empty token file if bootstrapping failed
      if [ ! -f "${PARENT_DIR}/secrets/consul_tokens.json" ]; then
        log "Creating default token file..."
        mkdir -p "${PARENT_DIR}/secrets" 2>/dev/null || sudo mkdir -p "${PARENT_DIR}/secrets" 2>/dev/null
        cat > /tmp/consul_tokens.json << EOF
{
  "bootstrap_token": "token_generation_failed",
  "nomad_token": "token_generation_failed",
  "traefik_token": "token_generation_failed",
  "vault_token": "token_generation_failed"
}
EOF
        sudo cp /tmp/consul_tokens.json "${PARENT_DIR}/secrets/consul_tokens.json"
        sudo chmod 600 "${PARENT_DIR}/secrets/consul_tokens.json"
        rm /tmp/consul_tokens.json
      fi
      
      warn "A placeholder token file has been created. You'll need to manually create tokens later."
      warn "Try running: ${PARENT_DIR}/bin/consul-tokens.sh when consul is fully operational"
    }
  fi
  # Restore error handling
  set -e
  
  # Step 10: Show access information
  show_access_info
  
  log "Consul setup completed. If you encounter issues, use the troubleshooting scripts."
  
  # Step 11: Output token information for subsequent steps
  if [ "${CONSUL_ENABLE_ACL}" = "true" ] && [ -f "${PARENT_DIR}/secrets/consul_tokens.json" ]; then
    # Check if the file is readable
    if [ -r "${PARENT_DIR}/secrets/consul_tokens.json" ]; then
      # Check if jq is available
      if command -v jq &> /dev/null; then
        # Safely extract values with default if missing
        BOOTSTRAP_TOKEN=$(jq -r '.bootstrap_token // "token_generation_failed"' "${PARENT_DIR}/secrets/consul_tokens.json" 2>/dev/null || echo "token_generation_failed")
        NOMAD_TOKEN=$(jq -r '.nomad_token // "token_generation_failed"' "${PARENT_DIR}/secrets/consul_tokens.json" 2>/dev/null || echo "token_generation_failed")
        TRAEFIK_TOKEN=$(jq -r '.traefik_token // "token_generation_failed"' "${PARENT_DIR}/secrets/consul_tokens.json" 2>/dev/null || echo "token_generation_failed")
        VAULT_TOKEN=$(jq -r '.vault_token // "token_generation_failed"' "${PARENT_DIR}/secrets/consul_tokens.json" 2>/dev/null || echo "token_generation_failed")
        
        if [[ "$BOOTSTRAP_TOKEN" == "token_generation_failed" ]]; then
          log "Token generation failed during startup."
          log "ACL is still enabled, but you'll need to create tokens manually when Consul is ready."
          log "You can do this using: ${PARENT_DIR}/bin/consul-tokens.sh"
        fi
        
        echo ""
        echo "================================================================="
        echo "CONSUL ACL TOKENS FOR SUBSEQUENT PLATFORM COMPONENTS"
        echo "================================================================="
        echo "These tokens will be needed for other platform components:"
        echo ""
        if [[ "$NOMAD_TOKEN" != "token_generation_failed" ]]; then
          echo "NOMAD TOKEN: ${NOMAD_TOKEN}"
        else
          echo "NOMAD TOKEN: Not available yet - generate manually when Consul is ready"
        fi
        
        if [[ "$TRAEFIK_TOKEN" != "token_generation_failed" ]]; then
          echo "TRAEFIK TOKEN: ${TRAEFIK_TOKEN}"
        else
          echo "TRAEFIK TOKEN: Not available yet - generate manually when Consul is ready"
        fi
        
        if [[ "$VAULT_TOKEN" != "token_generation_failed" ]]; then
          echo "VAULT TOKEN: ${VAULT_TOKEN}"
        else
          echo "VAULT TOKEN: Not available yet - generate manually when Consul is ready"
        fi
        
        echo ""
        echo "Tokens are saved to: ${PARENT_DIR}/secrets/consul_tokens.json"
        echo "Use ${PARENT_DIR}/bin/consul-tokens.sh to view or manage tokens"
        echo "================================================================="
        
        # Create configuration file for subsequent steps
        log "Creating token configuration file for subsequent installation steps..."
        
        # Create config directory if it doesn't exist
        mkdir -p "${PARENT_DIR}/config" 2>/dev/null
        
        # Create consul_tokens.conf with appropriate variables
        cat > "${PARENT_DIR}/config/consul_tokens.conf" << EOF
# Consul ACL tokens for platform components
# Generated on $(date)
# This file is automatically sourced by subsequent installation steps

# Consul bootstrap token (admin access)
CONSUL_BOOTSTRAP_TOKEN="${BOOTSTRAP_TOKEN}"

# Service-specific tokens
CONSUL_NOMAD_TOKEN="${NOMAD_TOKEN}"
CONSUL_TRAEFIK_TOKEN="${TRAEFIK_TOKEN}"
CONSUL_VAULT_TOKEN="${VAULT_TOKEN}"
EOF
        
        chmod 600 "${PARENT_DIR}/config/consul_tokens.conf"
        success "Token configuration saved for subsequent installation steps"
      else
        warn "jq command not found. Cannot parse token information."
        echo ""
        echo "================================================================="
        echo "CONSUL ACL TOKENS FOR SUBSEQUENT PLATFORM COMPONENTS"
        echo "================================================================="
        echo "Token file exists but couldn't be parsed (jq not installed)."
        echo "Tokens are saved to: ${PARENT_DIR}/secrets/consul_tokens.json"
        echo "Install jq and use ${PARENT_DIR}/bin/consul-tokens.sh to view tokens"
        echo "================================================================="
      fi
    else
      warn "Token file exists but is not readable: ${PARENT_DIR}/secrets/consul_tokens.json"
      echo ""
      echo "================================================================="
      echo "CONSUL ACL TOKENS FOR SUBSEQUENT PLATFORM COMPONENTS"
      echo "================================================================="
      echo "Token file exists but is not readable due to permissions."
      echo "Please check permissions on: ${PARENT_DIR}/secrets/consul_tokens.json"
      echo "================================================================="
    fi
  else
    if [ "${CONSUL_ENABLE_ACL}" = "true" ]; then
      log "Creating default token configuration for subsequent steps..."
      
      mkdir -p "${PARENT_DIR}/config" 2>/dev/null
      cat > "${PARENT_DIR}/config/consul_tokens.conf" << EOF
# Consul ACL tokens for platform components
# Generated on $(date) - PLACEHOLDER VALUES
# This file is automatically sourced by subsequent installation steps
# NOTE: You'll need to update these tokens manually using consul-tokens.sh

# Consul bootstrap token (admin access)
CONSUL_BOOTSTRAP_TOKEN="token_generation_failed"

# Service-specific tokens
CONSUL_NOMAD_TOKEN="token_generation_failed"
CONSUL_TRAEFIK_TOKEN="token_generation_failed"
CONSUL_VAULT_TOKEN="token_generation_failed"
EOF
      chmod 600 "${PARENT_DIR}/config/consul_tokens.conf"
      
      warn "ACL enabled but no token file was generated. Created a placeholder one."
      warn "You'll need to manually create tokens once Consul is fully operational."
      warn "Use ${PARENT_DIR}/bin/consul-tokens.sh to create and manage tokens."
    fi
  fi

  # Add this new line to display Nomad token and pause
  display_nomad_token_and_pause
  
  log "Consul setup completed. If you encounter issues, use the troubleshooting scripts."

  success "Consul setup process finished"
}

# Deploy Consul using direct Docker command
deploy_consul_docker() {
  log "Deploying Consul using direct Docker command..."
  
  log "Using IP address: ${CONSUL_BIND_ADDR} for Consul"
  
  # Check if Docker is available
  if ! command -v docker &>/dev/null; then
    error "Docker is not available. Please install Docker first."
  fi
  
  # Stop and remove any existing Consul container
  log "Stopping any existing Consul container..."
  sudo docker stop consul 2>/dev/null || true
  sudo docker rm consul 2>/dev/null || true
  
  # Ensure config directory has correct permissions
  if [ -d "${CONFIG_DIR}/consul" ]; then
    log "Setting appropriate permissions for Consul config directory..."
    sudo chmod -R 755 "${CONFIG_DIR}/consul"
    sudo find "${CONFIG_DIR}/consul" -name "*.json" -exec chmod 644 {} \; 2>/dev/null || true
    
    # Try to set proper ownership
    sudo chown -R 100:100 "${CONFIG_DIR}/consul" 2>/dev/null || true
  fi
  
  # Run the start script
  log "Starting Consul container..."
  PRIMARY_IP="${CONSUL_BIND_ADDR}" "${PARENT_DIR}/bin/start-consul.sh"
  
  # Wait for Consul to be ready
  log "Waiting for Consul to be ready..."
  sleep 15
  
  # Check if Consul is running
  local protocol="http"
  local insecure=""
  if [ "${CONSUL_ENABLE_SSL:-false}" = "true" ]; then
    protocol="https"
    insecure="-k"
  fi
  
  if ! curl -s ${insecure} ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/status/leader > /dev/null; then
    warn "Consul might not be fully operational yet. Please check status manually with: sudo docker logs consul"
    if ! sudo docker ps | grep -q "consul.*Up"; then
      log "Consul container is not running. Checking logs:"
      sudo docker logs consul
      warn "Please fix the issues and restart the container manually with: sudo ${PARENT_DIR}/bin/start-consul.sh"
    fi
  else
    success "Consul is running and responding to requests"
  fi

  # Create a reference file
  mkdir -p $JOB_DIR
  cat > $JOB_DIR/consul.reference << EOF
# Note: Consul was deployed directly as a Docker container
# To restart: ${PARENT_DIR}/bin/start-consul.sh
# To stop: ${PARENT_DIR}/bin/stop-consul.sh
# To view logs: sudo docker logs consul (or use consul-logs.sh)
# To check status: ${PARENT_DIR}/bin/consul-status.sh
# Container name: consul
# Image: hashicorp/consul:${CONSUL_VERSION}
# IP address: ${CONSUL_BIND_ADDR}
# HTTP port: ${CONSUL_HTTP_PORT}
# DNS port: ${CONSUL_DNS_PORT}
# SSL enabled: ${CONSUL_ENABLE_SSL:-false}
# ACL enabled: ${CONSUL_ENABLE_ACL:-false}
EOF

  success "Consul deployment completed"
}

# Execute main function
main "$@"