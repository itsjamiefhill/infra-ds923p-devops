#!/bin/bash
# uninstall-utils.sh
# Shared utility functions for uninstall scripts

# Set environment
set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
LOGS_DIR="${SCRIPT_DIR}/logs"

# Load configuration
load_config() {
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
  
  # The token is now passed via environment variable from the main script
  # We don't need to load it here anymore
  if [ -n "${NOMAD_TOKEN}" ]; then
    log "Nomad token already set in environment"
  else
    log "No Nomad token in environment"
  fi
}

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

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to setup logging
setup_logging() {
  mkdir -p "${LOGS_DIR}"
  if [ ! -f "${LOGS_DIR}/uninstall.log" ]; then
    echo "=== Uninstallation started at $(date) ===" > "${LOGS_DIR}/uninstall.log"
  else
    echo "=== Continuing uninstallation at $(date) ===" >> "${LOGS_DIR}/uninstall.log"
  fi
}

# Function to check if Nomad is available
check_nomad() {
  log "Checking Nomad availability..."
  if ! command_exists nomad; then
    warn "Nomad is not available. Some operations will be skipped."
    return 1
  fi
  
  if ! nomad version > /dev/null 2>&1; then
    warn "Nomad is installed but not responding. Some operations will be skipped."
    return 1
  fi
  
  success "Nomad is available"
  return 0
}

# Function to check if Docker is available
check_docker() {
  log "Checking Docker availability..."
  if ! command_exists docker; then
    warn "Docker is not available. Some cleanup operations will be skipped."
    return 1
  fi
  
  # Check if Docker is accessible
  if ! sudo docker info &>/dev/null; then
    warn "Docker is not accessible by the current user. Some cleanup operations may fail."
    return 1
  fi
  
  success "Docker is available and accessible"
  return 0
}

# Initialize the environment before any script runs
initialize() {
  setup_logging
  load_config
  log "Uninstall utilities loaded"
}

# Call initialize function to set up the environment
initialize