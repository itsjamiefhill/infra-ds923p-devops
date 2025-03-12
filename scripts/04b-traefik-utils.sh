#!/bin/bash
# 04b-traefik-utils.sh
# Certificate setup functions for Traefik deployment

# Function to setup certificates
setup_certificates() {
  log "Setting up wildcard certificate for Traefik..."
  
  # Create certificates directory if it doesn't exist
  mkdir -p "${CONFIG_DIR}/certs"
  
  # Create data directory for certificates with sudo if needed
  if [ ! -d "${DATA_DIR}/certificates" ]; then
    log "Creating certificates directory with sudo: ${DATA_DIR}/certificates"
    sudo mkdir -p "${DATA_DIR}/certificates"
    sudo chmod 755 "${DATA_DIR}/certificates"
  fi
  
  # Resolve certificate paths - handle both absolute and relative paths
  if [[ "${WILDCARD_CERT_PATH}" == /* ]]; then
    # It's an absolute path
    FULL_CERT_PATH="${WILDCARD_CERT_PATH}"
  else
    # Try different relative path options in order of likelihood
    if [ -f "${PARENT_DIR}/${WILDCARD_CERT_PATH}" ]; then
      FULL_CERT_PATH="${PARENT_DIR}/${WILDCARD_CERT_PATH}"
    elif [ -f "${SCRIPT_DIR}/${WILDCARD_CERT_PATH}" ]; then
      FULL_CERT_PATH="${SCRIPT_DIR}/${WILDCARD_CERT_PATH}"
    elif [ -f "${WILDCARD_CERT_PATH}" ]; then
      FULL_CERT_PATH="$(pwd)/${WILDCARD_CERT_PATH}"
    else
      FULL_CERT_PATH=""
    fi
  fi
  
  if [[ "${WILDCARD_KEY_PATH}" == /* ]]; then
    # It's an absolute path
    FULL_KEY_PATH="${WILDCARD_KEY_PATH}"
  else
    # Try different relative path options in order of likelihood
    if [ -f "${PARENT_DIR}/${WILDCARD_KEY_PATH}" ]; then
      FULL_KEY_PATH="${PARENT_DIR}/${WILDCARD_KEY_PATH}"
    elif [ -f "${SCRIPT_DIR}/${WILDCARD_KEY_PATH}" ]; then
      FULL_KEY_PATH="${SCRIPT_DIR}/${WILDCARD_KEY_PATH}"
    elif [ -f "${WILDCARD_KEY_PATH}" ]; then
      FULL_KEY_PATH="$(pwd)/${WILDCARD_KEY_PATH}"
    else
      FULL_KEY_PATH=""
    fi
  fi
  
  log "Resolved certificate path: ${FULL_CERT_PATH}"
  log "Resolved key path: ${FULL_KEY_PATH}"
  
  # Check if the resolved files exist
  if [ -n "${FULL_CERT_PATH}" ] && [ -n "${FULL_KEY_PATH}" ] && [ -f "${FULL_CERT_PATH}" ] && [ -f "${FULL_KEY_PATH}" ]; then
    log "Certificate files found at resolved paths"
    
    # Copy to the config directory with standard names
    cp "${FULL_CERT_PATH}" "${CONFIG_DIR}/certs/wildcard.crt"
    cp "${FULL_KEY_PATH}" "${CONFIG_DIR}/certs/wildcard.key"
    log "Certificate files copied to ${CONFIG_DIR}/certs/"
  else
    # If we couldn't find the cert files using the provided paths, try to generate self-signed ones
    log "Specified certificate files not found. Will create self-signed certificates instead."
    
    if ! command -v openssl &> /dev/null; then
      error "Certificate files not found and openssl is not available. Please install openssl or provide valid certificate paths."
    fi
    
    log "Generating self-signed wildcard certificate..."
    
    # Default to homelab.local if DOMAIN is not set
    local domain=${DOMAIN:-"homelab.local"}
    
    # Generate self-signed wildcard cert
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout "${CONFIG_DIR}/certs/wildcard.key" \
      -out "${CONFIG_DIR}/certs/wildcard.crt" \
      -subj "/CN=*.${domain}" \
      -addext "subjectAltName=DNS:*.${domain},DNS:${domain}" || \
      error "Failed to generate self-signed certificates"
    
    log "Self-signed wildcard certificate generated for *.${domain}"
  fi
  
  # Copy certificates to the data directory with sudo
  log "Copying certificates to Nomad volume directory with sudo..."
  sudo cp "${CONFIG_DIR}/certs/wildcard.crt" "${DATA_DIR}/certificates/"
  sudo cp "${CONFIG_DIR}/certs/wildcard.key" "${DATA_DIR}/certificates/"
  sudo chmod 644 "${DATA_DIR}/certificates/wildcard.crt"
  sudo chmod 600 "${DATA_DIR}/certificates/wildcard.key"
  
  # Fix permissions for Nomad to access the certificates
  log "Setting permissions on certificate directory for Nomad..."
  # Try to set ownership to nomad user first, fall back to current user if that fails
  sudo chown -R nomad:users "${DATA_DIR}/certificates" 2>/dev/null || \
    sudo chown -R $(whoami):$(id -gn) "${DATA_DIR}/certificates"
  sudo chmod -R 755 "${DATA_DIR}"
  
  # Using Docker volumes instead of Nomad volumes for Synology compatibility
  log "Skipping Nomad volume creation (using Docker volumes instead for Synology compatibility)"
  
  success "Certificate setup completed"
}