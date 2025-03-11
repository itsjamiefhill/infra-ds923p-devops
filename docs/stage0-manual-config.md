I'll create the stage0-manual-config.md document for you:

# Stage 0: Manual Configuration for Synology DS923+

This document provides step-by-step instructions for the initial manual setup (Stage 0) of your Synology DS923+ before deploying the HomeLab DevOps Platform.

## Table of Contents

1. [Hardware Setup](#hardware-setup)
2. [DSM Installation and Configuration](#dsm-installation-and-configuration)
3. [Network Configuration](#network-configuration)
4. [Storage Configuration](#storage-configuration)
5. [User Account Setup](#user-account-setup)
6. [Package Installation](#package-installation)
7. [SSH Configuration](#ssh-configuration)
8. [Firewall Configuration](#firewall-configuration)
9. [Nomad Installation](#nomad-installation)
10. [Directory Structure Setup](#directory-structure-setup)
11. [Verification Checklist](#verification-checklist)
12. [Next Steps](#next-steps)

## Hardware Setup

### RAM Installation

The DS923+ comes with 8GB by default. Upgrade to 32GB:

1. Power off the Synology NAS
2. Remove the drive bays to access the RAM slots
3. Remove the existing RAM module(s)
4. Install the 32GB RAM modules (2x16GB)
5. Replace the drive bays
6. Power on the Synology NAS
7. Verify RAM is recognized in DSM > Control Panel > Info Center

### Drive Installation

Install 4x 4TB HDDs:
1. Power off the Synology NAS (if not already off)
2. Insert the 4TB HDDs into the drive bays
3. Secure drives in the bays according to Synology's instructions
4. Replace the drive bays in the NAS
5. Power on the Synology NAS

### Network Connection

1. Connect the Synology NAS to your network using the Ethernet port
2. Ensure the connection is stable and the link light is on

## DSM Installation and Configuration

### DSM Installation

1. Power on the Synology DS923+
2. From a computer on the same network, open a web browser
3. Go to [find.synology.com](http://find.synology.com) or [diskstation:5000](http://diskstation:5000)
4. Follow the DSM installation wizard:
   - When prompted, install the latest DSM version
   - Set up an administrator account with a strong password
   - Configure update settings to automatically install important updates

### Initial DSM Configuration

1. Once logged into DSM, go to **Control Panel**
2. Configure **Regional Options**:
   - Set the correct time zone
   - Enable NTP server synchronization with reliable servers:
     - time.google.com
     - time.cloudflare.com
     - pool.ntp.org

3. Configure **Hardware & Power**:
   - Set power schedule if desired
   - Configure fan speed
   - Set up USB/UPS settings if applicable

4. Run DSM updates:
   - Go to **Control Panel** > **Update & Restore**
   - Click **Check for Updates**
   - Install all available updates
   - Restart if required

## Network Configuration

### Static IP Configuration

1. Go to **Control Panel** > **Network** > **Network Interface**
2. Select your primary network interface (likely "LAN 1") and click **Edit**
3. Select **Use manual configuration**
4. Configure the following:
   - IP Address: 10.0.4.10 (or your preferred static IP)
   - Subnet Mask: 255.255.255.0
   - Gateway: 10.0.4.1 (your router IP)
   - DNS Server: 10.0.4.1 (your router IP or preferred DNS)
5. Click **OK** to apply changes

### Network Service Configuration

1. Go to **Control Panel** > **Network** > **Network Service**
2. Configure the following:
   - **SMB Service**: Enable SMB service
   - **Terminal & SNMP**: Enable SSH service (we'll secure it later)
   - **DSM Settings**: Configure HTTPS connection
   - **Advanced Settings**: Enable P2P download bandwidth control if needed

## Storage Configuration

### Storage Pool Creation

1. Open **Storage Manager** from DSM main menu
2. Go to **Storage Pool**
3. Click **Create** to launch the creation wizard
4. Select **Create storage pool**
5. Choose **Better performance** (RAID 10)
6. Select all 4 HDDs
7. Click **Next**
8. Review the configuration and click **Apply**
9. Wait for the storage pool creation to complete

### Volume Creation

1. In **Storage Manager**, go to **Volume**
2. Click **Create** > **Create volume**
3. Select **Create on storage pool**
4. Choose the storage pool you just created
5. For the first volume:
   - Name: volume1
   - Description: devops
   - Size: 2TB
   - File System: Btrfs (recommended)
6. Click **Next** and then **Apply**
7. Create a second volume:
   - Name: volume2
   - Description: data
   - Size: Remaining space (approximately 6TB)
   - File System: Btrfs (recommended)
8. Click **Next** and then **Apply**

### Shared Folder Setup

1. Go to **Control Panel** > **Shared Folder**
2. Create the following shared folders:
   - **Name**: nomad
     - **Description**: Nomad configuration and data
     - **Location**: volume1
     - **Advanced settings**: Enable encryption if desired
   - **Name**: logs
     - **Description**: System and application logs
     - **Location**: volume1
   - **Name**: backups
     - **Description**: System and service backups
     - **Location**: volume2
   - **Name**: datasets
     - **Description**: User data and datasets
     - **Location**: volume2

## User Account Setup

### Service Accounts

1. Go to **Control Panel** > **User & Group**
2. Create the following user accounts:
   - **Username**: backup_worker
     - **Description**: Account for backup operations
     - **Password**: Generate and store a strong password
     - **Groups**: Add to the "users" group
     - **Permissions**: Read/Write access to "backups" folder, Read-only to others
   - **Username**: dev_worker
     - **Description**: Account for development operations
     - **Password**: Generate and store a strong password
     - **Groups**: Add to the "users" group
     - **Permissions**: Read/Write access to development folders

### Group Configuration

1. Go to **Control Panel** > **User & Group** > **Group**
2. Create a new group:
   - **Name**: devops
   - **Description**: Group for DevOps platform administrators
3. Add your main user account to this group
4. Configure appropriate shared folder permissions for this group

## Package Installation

### Required Packages

1. Open **Package Center** from DSM main menu
2. Install the following packages:
   - **Container Manager**: For Docker container management
   - **Text Editor**: For editing configuration files
   - **Hyper Backup**: For backup management
   - **Resource Monitor**: For system monitoring

### Configure Container Manager

After installation:
1. Go to Container Manager
2. No additional configuration is needed at this time, as we'll be using Nomad for container orchestration

## SSH Configuration

### Secure SSH Access

1. Go to **Control Panel** > **Terminal & SNMP** > **Terminal**
2. Ensure **Enable SSH service** is checked
3. Set **Port** to 22 (or a custom port if preferred)
4. Keep **Enable telnet service** unchecked for security
5. Apply settings

### SSH Key Authentication

1. On your client machine, generate an SSH key pair if you don't already have one:
   ```bash
   ssh-keygen -t ed25519 -C "your_email@example.com"
   ```

2. Copy your public key to the Synology:
   ```bash
   ssh-copy-id -i ~/.ssh/id_ed25519.pub your-username@synology-ip
   ```

3. Test SSH login with key authentication:
   ```bash
   ssh your-username@synology-ip
   ```

4. If successful, restrict SSH access by IP:
   ```bash
   # SSH into your Synology
   ssh your-username@synology-ip

   # Edit SSH configuration
   sudo vi /etc/ssh/sshd_config

   # Add the following line (replace with your network range)
   AllowUsers your-username@10.0.4.*

   # Restart SSH service
   sudo synoservicecfg --restart sshd
   ```

## Firewall Configuration

### Configure Synology Firewall

1. Go to **Control Panel** > **Security** > **Firewall**
2. Enable firewall and create a profile for your network interface
3. Set default action to **Deny**
4. Add the following rules:
   - **Allow SSH**: 
     - Source: Your management IPs only (e.g., 10.0.4.5)
     - Port: 22 (or your custom SSH port)
     - Protocol: TCP
     - Action: Allow
   - **Allow Web Access**:
     - Source: Your local network (10.0.4.0/24)
     - Ports: 80, 443, 5000, 5001
     - Protocol: TCP
     - Action: Allow
   - **Allow Nomad**:
     - Source: Your local network (10.0.4.0/24)
     - Ports: 4646-4648
     - Protocol: TCP
     - Action: Allow
   - **Allow Platform Services**:
     - Source: Your local network (10.0.4.0/24)
     - Ports: 8300-8302, 8500, 8600
     - Protocol: TCP
     - Action: Allow
   - **Add UDP ports for Consul**:
     - Source: Your local network (10.0.4.0/24)
     - Ports: 8301-8302, 8600
     - Protocol: UDP
     - Action: Allow
5. Apply the rules

## Nomad Installation

### Install Nomad

1. Download the Synology Nomad SPK package from [github.com/prabirshrestha/synology-nomad](https://github.com/prabirshrestha/synology-nomad)
2. In DSM, go to **Package Center**
3. Click **Manual Install**
4. Browse to the downloaded SPK file and follow the installation wizard
5. Accept the defaults when prompted

### Verify Nomad Installation

1. After installation, SSH into your Synology:
   ```bash
   ssh your-username@synology-ip
   ```

2. Verify Nomad is running:
   ```bash
   systemctl status nomad
   ```

3. If not running, start it:
   ```bash
   sudo systemctl start nomad
   ```

4. Enable auto-start:
   ```bash
   sudo systemctl enable nomad
   ```

### Access Nomad UI

1. From your browser, access the Nomad UI:
   ```
   http://synology-ip:4646/ui/
   ```

2. Verify you can see the Nomad dashboard

### Create Management Token

If ACLs are enabled (they may not be by default):

1. Bootstrap ACLs:
   ```bash
   nomad acl bootstrap
   ```

2. Save the management token securely
3. Export the token for CLI use:
   ```bash
   export NOMAD_TOKEN=your-management-token
   ```

## Directory Structure Setup

### Create Basic Directory Structure

1. SSH into your Synology:
   ```bash
   ssh your-username@synology-ip
   ```

2. Create the directory structure:
   ```bash
   # Main directories
   mkdir -p /volume1/docker/nomad/config
   mkdir -p /volume1/docker/nomad/jobs
   mkdir -p /volume1/logs/platform

   # Storage class directories
   mkdir -p /volume1/docker/nomad/volumes/high_performance
   mkdir -p /volume1/docker/nomad/volumes/high_capacity
   mkdir -p /volume1/docker/nomad/volumes/standard

   # Service directories
   mkdir -p /volume1/docker/nomad/volumes/consul_data
   mkdir -p /volume1/docker/nomad/volumes/vault_data
   mkdir -p /volume1/docker/nomad/volumes/prometheus_data
   mkdir -p /volume1/docker/nomad/volumes/grafana_data
   mkdir -p /volume1/docker/nomad/volumes/loki_data
   mkdir -p /volume1/docker/nomad/volumes/registry_data
   mkdir -p /volume1/docker/nomad/volumes/keycloak_data
   mkdir -p /volume1/docker/nomad/volumes/homepage_data
   mkdir -p /volume1/docker/nomad/volumes/certificates

   # Backup directories
   mkdir -p /volume2/backups/system
   mkdir -p /volume2/backups/services
   mkdir -p /volume2/datasets
   ```

3. Set permissions:
   ```bash
   # Set ownership (replace your-username with your actual username)
   chown -R your-username:users /volume1/nomad
   chown -R your-username:users /volume1/logs
   chown -R your-username:users /volume2/backups
   chown -R your-username:users /volume2/datasets

   # Set permissions
   chmod -R 755 /volume1/nomad
   chmod -R 755 /volume1/logs
   chmod -R 755 /volume2/backups
   chmod -R 755 /volume2/datasets

   # Special permissions for certain directories
   chmod 777 /volume1/docker/nomad/volumes/consul_data
   ```

## Verification Checklist

Before proceeding to Stage 1, verify:

- [ ] Synology DS923+ hardware is properly set up with 32GB RAM
- [ ] DSM is installed and updated to the latest version
- [ ] Network is configured with a static IP
- [ ] Storage pools and volumes are correctly configured
- [ ] Required shared folders are created
- [ ] Necessary user accounts and groups are set up
- [ ] Required packages are installed
- [ ] SSH is configured securely with key authentication
- [ ] Firewall is configured with appropriate rules
- [ ] Nomad is installed and running
- [ ] Directory structure is created with correct permissions
- [ ] Nomad UI is accessible
- [ ] Management tokens are created and saved (if using ACLs)

## Next Steps

Once you have completed all the Stage 0 manual configuration steps and verified your setup using the checklist, you are ready to proceed to Stage 1: Core Platform Deployment.

To begin Stage 1:

1. Clone the HomeLab DevOps Platform repository:
   ```bash
   git clone https://github.com/yourusername/homelab-devops.git
   cd homelab-devops
   ```

2. Make the installation script executable:
   ```bash
   chmod +x install.sh
   ```

3. Run the Stage 1 installation:
   ```bash
   ./install.sh
   ```

This will start the automated deployment of the core platform components as described in the [Stages Overview](stages-overview.md) document.