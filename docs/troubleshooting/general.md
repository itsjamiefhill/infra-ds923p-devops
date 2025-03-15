# 2. troubleshooting/general.md
# General Troubleshooting

This document covers general troubleshooting approaches, installation issues, and common error messages for the HomeLab DevOps Platform.

## Table of Contents

1. [Checking System Status](#checking-system-status)
2. [Restarting Services](#restarting-services)
3. [Checking Logs](#checking-logs)
4. [Installation Issues](#installation-issues)
5. [Resource Constraints](#resource-constraints)
6. [Common Error Messages](#common-error-messages)

## Checking System Status

To check the status of all Nomad jobs:

```bash
nomad job status
```

To check the status of a specific job:

```bash
nomad job status <job-name>
```

To check the allocation status and logs:

```bash
nomad alloc status <alloc-id>
nomad alloc logs <alloc-id>
```

## Restarting Services

To restart a service:

```bash
nomad job stop <job-name>
nomad job run jobs/<job-name>.hcl
```

## Checking Logs

Installation logs are stored in:

```
/volume1/logs/install.log
```

Service logs can be viewed through:

```bash
nomad alloc logs <alloc-id>
```

Or through the Grafana/Loki interface at:

```
https://grafana.homelab.local
```

## Installation Issues

### Script Execution Permissions

If you encounter permission errors:

```bash
chmod +x install.sh
chmod +x scripts/*.sh
```

### Missing Dependencies

If the script reports missing dependencies:

```bash
# For Synology
sudo apt-get update
sudo apt-get install -y curl jq unzip
```

### Nomad Not Running

If Nomad is not running:

```bash
# Check status
systemctl status nomad

# Start Nomad
systemctl start nomad
```

### Directory Permission Issues

If you encounter directory permission issues:

```bash
sudo chmod -R 755 /volume1/docker/nomad/volumes
sudo chown -R <your-user>:<your-group> /volume1/docker/nomad/volumes
```

## Resource Constraints

### Memory and CPU Issues

If services are being killed due to resource constraints:

1. Check resource usage:
   ```bash
   nomad alloc status <alloc-id> | grep Resources
   ```

2. Increase resource limits in your configuration:
   ```bash
   # Edit config/custom.conf
   VAULT_CPU=1000       # Increase from default 500
   VAULT_MEMORY=1024    # Increase from default 512
   ```

3. Redeploy the affected service:
   ```bash
   ./scripts/05-deploy-vault.sh
   ```

### Disk Space Issues

If you're running out of disk space:

1. Check disk usage:
   ```bash
   df -h /volume1
   ```

2. Clean up unused Docker images:
   ```bash
   docker system prune -a
   ```

3. Consider relocating volumes:
   ```bash
   # Edit config/custom.conf
   DATA_DIR=/volume2/docker/nomad/volumes  # Change to a different volume
   ```

## Common Error Messages

### "No such file or directory"

If you see "No such file or directory" errors:

1. Check if the directory exists:
   ```bash
   ls -la /path/to/directory
   ```

2. Create the directory if needed:
   ```bash
   sudo mkdir -p /path/to/directory
   ```

3. Verify script paths are correct:
   ```bash
   find . -name "*.sh" -exec grep -l "/path/to" {} \;
   ```

### "Permission denied"

If you see "Permission denied" errors:

1. Check file permissions:
   ```bash
   ls -la <file-or-directory>
   ```

2. Fix permissions:
   ```bash
   sudo chmod 755 <file-or-directory>
   sudo chown <user>:<group> <file-or-directory>
   ```

3. Run with sudo if needed:
   ```bash
   sudo ./scripts/<script-name>.sh
   ```

### "Connection refused"

If you see "Connection refused" errors:

1. Check if the service is running:
   ```bash
   nomad job status <job-name>
   ```

2. Verify the port is open:
   ```bash
   ss -tulpn | grep <port>
   ```

3. Check for firewall issues:
   ```bash
   sudo iptables -L
   ```

### "Invalid token"

If you see "Invalid token" errors with service APIs:

1. Check token validity:
   ```bash
   # For Nomad
   nomad acl token self
   
   # For Vault
   VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec -task vault ${VAULT_ALLOC} vault token lookup
   ```

2. Create a new token:
   ```bash
   # For Nomad
   nomad acl token create -name="new-management-token" -type="management"
   
   # For Vault
   nomad alloc exec -task vault ${VAULT_ALLOC} vault token create -policy=<policy-name>
   ```

3. Set the token in your environment:
   ```bash
   export NOMAD_TOKEN=<your-token>
   ```

### "Unauthorized" or "Permission denied" with Nomad API

If you're getting permission errors with Nomad:

1. Verify your token has the right permissions:
   ```bash
   nomad acl token self
   ```

2. Check your Nomad SSL configuration:
   ```bash
   echo $NOMAD_ADDR
   echo $NOMAD_TOKEN
   echo $NOMAD_CACERT
   echo $NOMAD_CLIENT_CERT
   echo $NOMAD_CLIENT_KEY
   ```

3. Setup Nomad SSL environment properly:
   ```bash
   export NOMAD_ADDR=https://127.0.0.1:4646
   export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
   export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
   export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem
   export NOMAD_TOKEN=<your-token>
   ```