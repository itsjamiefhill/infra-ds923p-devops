# Stage 0: Prerequisites and Synology DS923+ Setup

This document outlines the prerequisites and manual setup steps required before deploying the HomeLab DevOps platform. These steps constitute "Stage 0" of the deployment process.

This document is an overview of the stage 0 manual configuration required before stage 1. For a full, step by step process see: https://github.com/itsjamiefhill/infra-ds923p-config

## Hardware Requirements

### Synology DS923+ Specifications
- **CPU**: AMD Ryzen R1600 dual-core processor
- **RAM**: 32GB (upgraded from default 8GB)
- **Storage**: 4x 4TB HDDs configured in RAID10
- **Network**: 1GbE (or 10GbE with optional upgrade card)

### Storage Configuration
- RAID10 configuration for balance of performance and redundancy
- Provides approximately 8TB of usable storage
- Split into logical volumes:
  - Volume 1 "devops": For platform services (~2TB)
  - Volume 2 "data": For user data and backups (~6TB)

## Network Prerequisites

### Local Network
- Static IP address for Synology DS923+
- Local domain naming (e.g., `.homelab.local`)
- Network subnet: 10.0.4.0/24
- No external ports exposed to the internet

### DNS Configuration
- Local DNS server or hosts file entries for service names
- Configure Synology to use reliable NTP servers

## Software Prerequisites

### DSM Configuration
1. **Update DSM to Latest Version**
   - Control Panel > Update & Restore > Update
   - Apply all available updates

2. **Enable SSH**
   - Control Panel > Terminal & SNMP > Terminal
   - Check "Enable SSH service"
   - Set maximum connections to 5
   - Set port (default 22)
   - Enable key-based authentication (see Security section)

3. **Configure Firewall**
   - Control Panel > Security > Firewall
   - Create a profile for your network interface
   - Allow the following ports from 10.0.4.0/24:
     - SSH (22) - From specific management IPs only
     - Nomad (4646-4648)
     - Consul (8300-8302, 8500, 8600)
     - Traefik (80, 443, 8081)

4. **Install Required Packages**
   - Container Manager (from Package Center)
   - Text Editor (from Package Center)

### Nomad Installation

1. **Install Nomad SPK Package**
   - Download the SPK from [github.com/prabirshrestha/synology-nomad](https://github.com/prabirshrestha/synology-nomad)
   - Manual install through Package Center
   - Follow installation instructions from the repository

2. **Enable Nomad SSL**
   - Nomad SSL certificates are stored in `/var/packages/nomad/shares/nomad/etc/certs/`
   - Verify the following certificate files exist:
     - `nomad-ca.pem` - CA certificate
     - `nomad-cert.pem` - Client certificate
     - `nomad-key.pem` - Client key

3. **Configure Nomad SSL Environment Variables**
   - Add the following to your `.bashrc` or `.bash_profile`:
   ```bash
   export NOMAD_ADDR=https://127.0.0.1:4646
   export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
   export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
   export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem
   ```

4. **Verify Nomad Installation**
   - Access Nomad UI at https://your-synology-ip:4646
   - Note the HTTPS protocol due to SSL being enabled
   - Accept the self-signed certificate in your browser
   - Create a management token through the UI

## Security Setup

### SSH Key Authentication
1. **Generate SSH Key Pair on Client**
   ```bash
   ssh-keygen -t ed25519 -C "your_email@example.com"
   ```

2. **Copy Public Key to Synology**
   ```bash
   ssh-copy-id -i ~/.ssh/id_ed25519.pub your-username@synology-ip
   ```

3. **Restrict SSH Access** (Optional)
   - Edit `/etc/ssh/sshd_config`
   - Add: `AllowUsers your-username@10.0.4.*`
   - Restart SSH service

### Self-Signed Certificate Preparation
1. **Install OpenSSL** (on your client machine)
2. **Create Directory for Certificates**
   ```bash
   mkdir -p /volume1/certificates
   ```

3. **Store Nomad Token Securely**
   - Create a config file to store your Nomad token:
   ```bash
   mkdir -p /volume1/docker/nomad/config
   echo 'NOMAD_TOKEN="your-management-token"' > /volume1/docker/nomad/config/nomad_auth.conf
   chmod 600 /volume1/docker/nomad/config/nomad_auth.conf
   ```

## Directory Structure Setup

Create the required directories for the platform:
*N.B. docker directory is created by default when Container Manager synology package is installed*

```bash
# Create essential directories on volume1 (devops)
mkdir -p /volume1/docker/nomad/config
mkdir -p /volume1/docker/nomad/volumes/high_performance
mkdir -p /volume1/docker/nomad/volumes/high_capacity
mkdir -p /volume1/docker/nomad/volumes/standard
mkdir -p /volume1/logs/platform

# Create directories on volume2 (data)
mkdir -p /volume2/backups/system
mkdir -p /volume2/backups/services
mkdir -p /volume2/datasets

# Set ownership
chown -R your-username:users /volume1/docker/nomad
chown -R your-username:users /volume1/logs
chown -R your-username:users /volume2/backups
chown -R your-username:users /volume2/datasets

# Set permissions
chmod -R 755 /volume1/docker/nomad
chmod -R 755 /volume1/logs
chmod -R 755 /volume2/backups
chmod -R 755 /volume2/datasets
```

## Verification Checklist

Before proceeding to Stage 1, verify:

- [ ] DSM is updated to the latest version
- [ ] SSH is properly configured with key authentication
- [ ] Container Manager is installed and running
- [ ] Nomad is installed with SSL enabled and UI is accessible via HTTPS
- [ ] Nomad SSL certificates exist and are accessible
- [ ] Nomad environment variables are configured for SSL
- [ ] All required directories are created with proper permissions
- [ ] Network is properly configured with static IP
- [ ] Firewall is configured with appropriate rules

## Nomad ACL Bootstrap

Nomad uses an ACL system. Create a bootstrap token:

1. **Access the Nomad UI** at https://your-synology-ip:4646
2. **Navigate to ACL Tokens** and create a management token
3. **Save the Secret ID** in a secure location and in your nomad_auth.conf file

## Testing Nomad SSL Configuration

To verify your Nomad SSL configuration is working correctly:

```bash
# Test Nomad connectivity with SSL
nomad server members

# This should return a list of server members without SSL errors
# If you see errors about certificates, verify your environment variables
```

## Next Steps

Once all prerequisites are met, proceed to Stage 1 deployment by running the installation script as described in the main README.md.

## Troubleshooting

### Common Issues

1. **Nomad Not Starting**:
   - Check system resources
   - Verify no port conflicts
   - Check logs at `/volume1/logs/platform/nomad.log`

2. **Container Manager Issues**:
   - Ensure Docker storage has sufficient space
   - Check DSM resource monitor for any constraints

3. **Network Configuration Issues**:
   - Verify static IP is properly set
   - Ensure firewall rules are correctly applied
   - Test connectivity between services

4. **SSL Certificate Issues**:
   - Verify certificate paths in environment variables
   - Check certificate permissions (should be readable by your user)
   - Test with `curl -k https://127.0.0.1:4646/v1/agent/members` to bypass SSL verification

5. **Nomad CLI Authentication Errors**:
   - Ensure NOMAD_TOKEN is set correctly
   - Verify SSL environment variables are correctly set
   - Check if token has expired or been revoked

For more detailed troubleshooting, refer to the [Troubleshooting Guide](troubleshooting.md).