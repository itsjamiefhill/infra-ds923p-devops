#!/bin/bash
# uninstall.sh
# Main uninstall script that coordinates uninstallation of all components

# Set script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
LOGS_DIR="${SCRIPT_DIR}/logs"

# Define basic color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create logs directory
mkdir -p "${LOGS_DIR}"

# Basic implementation of utility functions
log() {
  echo -e "${BLUE}[INFO]${NC} $1"
  echo "[INFO] $1" >> "${LOGS_DIR}/uninstall.log" 2>/dev/null || true
}

warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
  echo "[WARNING] $1" >> "${LOGS_DIR}/uninstall.log" 2>/dev/null || true
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
  echo "[ERROR] $1" >> "${LOGS_DIR}/uninstall.log" 2>/dev/null || true
  exit 1
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
  echo "[SUCCESS] $1" >> "${LOGS_DIR}/uninstall.log" 2>/dev/null || true
}

confirm() {
  echo -e "${YELLOW}"
  read -p "$1 [y/N] " -n 1 -r
  echo -e "${NC}"
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      return 1
  fi
  return 0
}

# Read the Nomad token from the config file
read_nomad_token() {
  log "Reading Nomad token from ${CONFIG_DIR}/nomad_auth.conf"
  
  if [ -f "${CONFIG_DIR}/nomad_auth.conf" ]; then
    log "Token file found, loading..."
    source "${CONFIG_DIR}/nomad_auth.conf"
    if [ -n "$NOMAD_TOKEN" ]; then
      export NOMAD_TOKEN
      success "Nomad token loaded successfully"
      return 0
    else
      warn "Token file exists but NOMAD_TOKEN variable is empty"
    fi
  else
    warn "Token file not found at ${CONFIG_DIR}/nomad_auth.conf"
  fi
  
  # If we get here, no token was found or loaded
  if confirm "Would you like to enter a Nomad token manually?"; then
    echo -n "Enter Nomad token: "
    read -r NOMAD_TOKEN
    if [ -n "$NOMAD_TOKEN" ]; then
      export NOMAD_TOKEN
      log "Using manually entered token"
      
      # Save the token to the proper location
      mkdir -p "${CONFIG_DIR}"
      echo "NOMAD_TOKEN=\"${NOMAD_TOKEN}\"" > "${CONFIG_DIR}/nomad_auth.conf"
      log "Token saved to ${CONFIG_DIR}/nomad_auth.conf"
      return 0
    else
      warn "No token entered"
    fi
  fi
  
  warn "No Nomad token available. Some operations may fail."
  return 1
}

# Update child scripts to not load the token directly
update_child_scripts() {
  log "Checking child scripts to ensure they don't load the token directly..."
  
  for script in "${SCRIPTS[@]}"; do
    if grep -q "source.*nomad_auth.conf" "$script"; then
      log "Updating $script to skip token loading..."
      # Create a backup of the script
      cp "$script" "${script}.bak"
      
      # Replace any direct sourcing of the nomad_auth.conf file
      sed -i 's/source.*nomad_auth.conf/# Token provided by main script/g' "$script"
      
      # Add comment for clarity
      sed -i '1s/^/# NOTE: Nomad token is provided by the main uninstall.sh script\n/' "$script"
      
      success "Updated $script"
    fi
  done
}

# Main function
log "Initializing uninstall script..."

# Load Nomad token
read_nomad_token

# Display header
echo -e "\n${GREEN}==========================================================${NC}"
echo -e "${GREEN}    HomeLab DevOps Platform Complete Uninstallation     ${NC}"
echo -e "${GREEN}==========================================================${NC}"

# Confirm uninstallation
if ! confirm "This will remove artifacts generated during installation, but preserve all scripts. Continue?"; then
  echo -e "\n${YELLOW}Uninstallation cancelled.${NC}"
  exit 0
fi

# Find all uninstall scripts and sort them in reverse order
if [ -d "${SCRIPTS_DIR}" ]; then
  SCRIPT_FILES=$(find "${SCRIPTS_DIR}" -name "uninstall-[0-9][0-9]-*.sh" -type f | sort -r)
  if [ -z "$SCRIPT_FILES" ]; then
    warn "No uninstall scripts found in ${SCRIPTS_DIR}"
    if confirm "Would you like to exit and check the scripts directory first?"; then
      log "Exiting uninstallation process. Please check the scripts directory at ${SCRIPTS_DIR}"
      exit 0
    fi
  else
    # Convert to array
    mapfile -t SCRIPTS <<< "$SCRIPT_FILES"
  fi
else
  error "Scripts directory not found at ${SCRIPTS_DIR}"
fi

# Check if any scripts were found
if [ ${#SCRIPTS[@]} -eq 0 ]; then
  warn "No uninstall scripts found in ${SCRIPTS_DIR}"
  if confirm "Would you like to continue anyway? This will only run the main uninstall logic."; then
    log "Continuing with main uninstall logic only"
  else
    log "Exiting uninstallation process"
    exit 0
  fi
fi

# Update child scripts to not load the token directly
if confirm "Would you like to update child scripts to not load the Nomad token directly?"; then
  update_child_scripts
  log "Child scripts updated. The token will only be read by the main script."
else
  log "Skipping child script updates. Some scripts may still try to read the token."
fi

# Check that all scripts are executable
MISSING_SCRIPTS=0
for script in "${SCRIPTS[@]}"; do
  if [ ! -x "$script" ]; then
    warn "Script not executable: $(basename $script)"
    if confirm "Would you like to make $(basename $script) executable?"; then
      chmod +x "$script" || {
        warn "Failed to make $(basename $script) executable"
        MISSING_SCRIPTS=$((MISSING_SCRIPTS + 1))
      }
    else
      MISSING_SCRIPTS=$((MISSING_SCRIPTS + 1))
    fi
  fi
done

if [ $MISSING_SCRIPTS -gt 0 ]; then
  warn "$MISSING_SCRIPTS script(s) are not executable."
  if ! confirm "Continue anyway?"; then
    log "Exiting uninstallation process"
    exit 0
  fi
fi

# Uninstall services using the scripts in reverse order
log "Starting uninstallation in reverse order of deployment..."

# Count total scripts for progress tracking
TOTAL_SCRIPTS=${#SCRIPTS[@]}
CURRENT=1

# Run each script
for script in "${SCRIPTS[@]}"; do
  SCRIPT_NAME=$(basename "$script")
  COMPONENT=$(echo "$SCRIPT_NAME" | sed -n 's/uninstall-[0-9][0-9]-\(.*\)\.sh/\1/p')
  
  echo -e "\n${BLUE}Step $CURRENT of $TOTAL_SCRIPTS: Uninstalling ${COMPONENT^}${NC}"
  
  # Prepare environment variables to pass to the script
  ENV_VARS=(
    "SCRIPT_DIR=${SCRIPT_DIR}"
    "CONFIG_DIR=${CONFIG_DIR}" 
    "DATA_DIR=${DATA_DIR:-/volume1/docker/nomad/volumes}"
    "JOB_DIR=${JOB_DIR:-/volume1/docker/nomad/jobs}"
    "LOG_DIR=${LOG_DIR:-/volume1/logs}"
    "NOMAD_ADDR=${NOMAD_ADDR:-https://127.0.0.1:4646}"
    "NOMAD_CACERT=${NOMAD_CACERT:-/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem}"
    "NOMAD_CLIENT_CERT=${NOMAD_CLIENT_CERT:-/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem}"
    "NOMAD_CLIENT_KEY=${NOMAD_CLIENT_KEY:-/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem}"
  )
  
  # Add token if available
  if [ -n "$NOMAD_TOKEN" ]; then
    ENV_VARS+=("NOMAD_TOKEN=${NOMAD_TOKEN}")
  fi
  
  # Run the script with environment variables
  env "${ENV_VARS[@]}" "$script" || warn "${COMPONENT^} uninstallation encountered issues"
  
  CURRENT=$((CURRENT + 1))
done

# Restore original child scripts if backups exist
if confirm "Would you like to restore the original versions of the child scripts?"; then
  for script in "${SCRIPTS[@]}"; do
    if [ -f "${script}.bak" ]; then
      mv "${script}.bak" "$script"
      log "Restored original version of $script"
    fi
  done
  success "All script modifications have been reverted"
else
  log "Keeping updated scripts. The token will be read only by the main script in future runs."
fi

# Show summary
echo -e "\n${GREEN}==========================================================${NC}"
echo -e "${GREEN}      HomeLab DevOps Platform Uninstallation Complete    ${NC}"
echo -e "${GREEN}==========================================================${NC}"
echo -e "\n${BLUE}All generated artifacts have been uninstalled.${NC}"
echo -e "${BLUE}All scripts have been preserved for future reinstallation.${NC}"
echo -e "${BLUE}Log files are available at: ${LOGS_DIR}/uninstall.log${NC}"
echo -e "\nThank you for using the HomeLab DevOps Platform.\n"

exit 0