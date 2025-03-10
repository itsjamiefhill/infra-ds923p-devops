# HomeLab DevOps Platform Troubleshooting Guide for Synology DS923+

This guide provides solutions for common issues you might encounter with your HomeLab DevOps Platform on Synology DS923+.

## Table of Contents

1. [General Troubleshooting](#general-troubleshooting)
2. [Installation Issues](#installation-issues)
3. [Service-Specific Problems](#service-specific-problems)
   - [Consul](#consul)
   - [Traefik](#traefik)
   - [Vault](#vault)
   - [Docker Registry](#docker-registry)
   - [Monitoring Stack](#monitoring-stack)
   - [Logging Stack](#logging-stack)
   - [OIDC Authentication](#oidc-authentication)
   - [Homepage Dashboard](#homepage-dashboard)
4. [Network Issues](#network-issues)
5. [Volume and Data Issues](#volume-and-data-issues)
6. [Resource Constraints](#resource-constraints)
7. [DSM-Specific Issues](#dsm-specific-issues)
8. [Common Error Messages](#common-error-messages)

## General Troubleshooting

### Checking System Status

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

### Restarting Services

To restart a service:

```bash
nomad job stop <job-name>
nomad job run jobs/<job-name>.hcl
```

### Checking Logs

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

If you encounter directory permission errors:

```bash
sudo chmod -R 755 /volume1/nomad/volumes
sudo chown -R <your-user>:<your-group> /volume1/nomad/volumes
```

## Service-Specific Problems

### Consul

#### Consul Not Starting

If Consul fails to start:

1. Check if the ports are already in use:
   ```bash
   ss -tulpn | grep 8500
   ```

2. Make sure the data directory is writable:
   ```bash
   sudo chmod 777 /volume1/nomad/volumes/high_performance/consul_data
   ```

3. Check logs:
   ```bash
   nomad alloc logs <consul-alloc-id>
   ```

#### Consul UI Not Accessible

If you can't access the Consul UI:

1. Verify the job is running:
   ```bash
   nomad job status consul
   ```

2. Check if Traefik is correctly routing:
   ```bash
   curl -I -k https://consul.homelab.local
   ```

3. Verify host entry:
   ```bash
   ping consul.homelab.local
   ```

#### DNS Resolution Issues

If Consul DNS isn't working:

1. Check the dnsmasq configuration:
   ```bash
   cat /etc/dnsmasq.conf.d/10-consul
   ```

2. Test DNS resolution:
   ```bash
   dig @127.0.0.1 -p 8600 consul.service.consul
   ```

3. Restart dnsmasq:
   ```bash
   systemctl restart dnsmasq
   ```

### Traefik

#### Traefik Not Routing

If Traefik is not properly routing requests:

1. Check if Traefik is running:
   ```bash
   nomad job status traefik
   ```

2. Verify the dashboard is accessible:
   ```bash
   curl -I -k https://traefik.homelab.local/dashboard/
   ```

3. Check service registration in Consul:
   ```bash
   curl http://consul.service.consul:8500/v1/catalog/services
   ```

#### Certificate Issues

If you're having TLS certificate issues:

1. Check certificate validity:
   ```bash
   openssl x509 -in /volume1/nomad/config/certs/homelab.crt -text -noout
   ```

2. Verify certificate is mounted correctly:
   ```bash
   nomad alloc exec <traefik-alloc-id> ls -la /etc/traefik/certs
   ```

3. Import certificate to your client device:
   - Windows: Import to "Trusted Root Certification Authorities"
   - macOS: Import to Keychain, set to "Always Trust"
   - Linux: Add to `/usr/local/share/ca-certificates/` and run `update-ca-certificates`

### Vault

#### Vault Sealed

If Vault is sealed and needs to be unsealed:

```bash
# Check if sealed
VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
nomad alloc exec -task vault ${VAULT_ALLOC} vault status

# Unseal using keys
nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key1>
nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key2>
nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key3>
```

#### Vault Authentication Issues

If you can't authenticate with Vault:

1. Check if Vault is unsealed:
   ```bash
   VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec -task vault ${VAULT_ALLOC} vault status
   ```

2. Reset the root token (if needed):
   ```bash
   nomad alloc exec -task vault ${VAULT_ALLOC} vault operator generate-root -init
   # Follow the prompts to generate a new root token
   ```

3. Verify OIDC configuration:
   ```bash
   nomad alloc exec -task vault ${VAULT_ALLOC} vault auth list
   ```

#### Secret Engines Issues

If you're having issues with Vault secret engines:

```bash
# List enabled secret engines
VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
nomad alloc exec -task vault ${VAULT_ALLOC} vault secrets list

# Enable a secret engine
nomad alloc exec -task vault ${VAULT_ALLOC} vault secrets enable -path=<path> <engine>

# Troubleshoot a specific engine
nomad alloc exec -task vault ${VAULT_ALLOC} vault read <path>/config
```

### Docker Registry

#### Push/Pull Issues

If you can't push or pull images:

1. Verify registry is running:
   ```bash
   nomad job status docker-registry
   ```

2. Test registry manually:
   ```bash
   curl -I -k https://registry.homelab.local/v2/
   ```

3. Ensure certificate trust:
   ```bash
   # Create directory for certificates
   sudo mkdir -p /etc/docker/certs.d/registry.homelab.local:5000

   # Copy your self-signed certificate
   sudo cp /volume1/nomad/config/certs/homelab.crt /etc/docker/certs.d/registry.homelab.local:5000/ca.crt

   # Restart Docker
   sudo systemctl restart docker
   ```

#### Storage Issues

If the registry is having storage problems:

1. Check available space:
   ```bash
   df -h /volume1/nomad/volumes/high_capacity/registry_data
   ```

2. Run garbage collection:
   ```bash
   REGISTRY_ALLOC=$(nomad job allocs -job docker-registry -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec -task registry ${REGISTRY_ALLOC} registry garbage-collect /etc/docker/registry/config.yml
   ```

### Monitoring Stack

#### Prometheus Issues

If Prometheus is not collecting metrics:

1. Check if Prometheus is running:
   ```bash
   nomad job status prometheus
   ```

2. Verify targets in the Prometheus UI:
   ```
   https://prometheus.homelab.local/targets
   ```

3. Check scrape configuration:
   ```bash
   PROMETHEUS_ALLOC=$(nomad job allocs -job prometheus -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec -task prometheus ${PROMETHEUS_ALLOC} cat /etc/prometheus/prometheus.yml
   ```

#### Grafana Issues

If Grafana dashboards aren't working:

1. Verify Grafana is running:
   ```bash
   nomad job status grafana
   ```

2. Check data source configuration:
   ```
   https://grafana.homelab.local/datasources
   ```

3. Verify OIDC authentication:
   ```bash
   GRAFANA_ALLOC=$(nomad job allocs -job grafana -latest | tail -n +2 | awk '{print $1}')
   nomad alloc logs ${GRAFANA_ALLOC}
   ```

4. Check Grafana permissions:
   ```bash
   ls -la /volume1/nomad/volumes/standard/grafana_data
   sudo chown -R 472:472 /volume1/nomad/volumes/standard/grafana_data
   ```

### Logging Stack

#### Loki Issues

If logs aren't appearing in Loki:

1. Verify Loki is running:
   ```bash
   nomad job status loki
   ```

2. Check Promtail configuration:
   ```bash
   PROMTAIL_ALLOC=$(nomad job allocs -job promtail -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec -task promtail ${PROMTAIL_ALLOC} cat /etc/promtail/config.yml
   ```

3. Test log submission manually:
   ```bash
   curl -X POST -H "Content-Type: application/json" -d '{"streams": [{"stream": {"job": "test"}, "values": [["'"$(date +%s)000000000"'", "test message"]]}]}' http://loki.service.consul:3100/loki/api/v1/push
   ```

#### Promtail Issues

If Promtail isn't collecting logs:

1. Verify Promtail is running:
   ```bash
   nomad job status promtail
   ```

2. Check file permissions for log files:
   ```bash
   ls -la /var/log/
   ```

3. Check Promtail logs:
   ```bash
   PROMTAIL_ALLOC=$(nomad job allocs -job promtail -latest | tail -n +2 | awk '{print $1}')
   nomad alloc logs ${PROMTAIL_ALLOC}
   ```

4. Verify Docker log paths:
   ```bash
   ls -la /var/packages/ContainerManager/var/docker/containers/
   ```

### OIDC Authentication

#### Keycloak Issues

If Keycloak is not working correctly:

1. Verify Keycloak is running:
   ```bash
   nomad job status keycloak
   ```

2. Check Keycloak logs:
   ```bash
   KEYCLOAK_ALLOC=$(nomad job allocs -job keycloak -latest | tail -n +2 | awk '{print $1}')
   nomad alloc logs ${KEYCLOAK_ALLOC}
   ```

3. Check database connection:
   ```bash
   ls -la /volume1/nomad/volumes/standard/keycloak_data
   ```

#### OIDC Proxy Issues

If the OIDC proxy isn't authenticating properly:

1. Check if the proxy is running:
   ```bash
   nomad job status oidc-proxy
   ```

2. Verify configuration:
   ```bash
   OIDC_ALLOC=$(nomad job allocs -job oidc-proxy -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec ${OIDC_ALLOC} env | grep CLIENT
   ```

3. Check logs for authentication failures:
   ```bash
   nomad alloc logs ${OIDC_ALLOC}
   ```

#### Service Integration Issues

If services aren't integrating with OIDC:

1. Check Traefik middleware configuration:
   ```bash
   curl http://consul.service.consul:8500/v1/catalog/service/oidc-proxy | jq
   ```

2. Verify service-specific OIDC settings:
   ```bash
   # For Grafana
   GRAFANA_ALLOC=$(nomad job allocs -job grafana -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec ${GRAFANA_ALLOC} env | grep OAUTH
   ```

### Homepage Dashboard

#### Dashboard Not Loading

If the Homepage dashboard isn't loading:

1. Verify the job is running:
   ```bash
   nomad job status homepage
   ```

2. Check configuration files:
   ```bash
   HOMEPAGE_ALLOC=$(nomad job allocs -job homepage -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec ${HOMEPAGE_ALLOC} ls -la /app/config
   ```

3. Test direct access:
   ```bash
   curl http://localhost:3000/
   ```

#### Service Discovery Issues

If services aren't appearing on the dashboard:

1. Check Consul integration:
   ```bash
   HOMEPAGE_ALLOC=$(nomad job allocs -job homepage -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec ${HOMEPAGE_ALLOC} env | grep CONSUL
   ```

2. Verify service tags:
   ```bash
   curl http://consul.service.consul:8500/v1/catalog/services | jq '.' | grep homepage
   ```

3. Check Homepage configuration:
   ```bash
   nomad alloc exec ${HOMEPAGE_ALLOC} cat /app/config/services.yaml
   ```

## Network Issues

### DNS Resolution Problems

If you're having DNS resolution issues:

1. Check host entries:
   ```bash
   cat /etc/hosts | grep homelab
   ```

2. Verify DNS service in Consul:
   ```bash
   dig @127.0.0.1 -p 8600 vault.service.consul
   ```

3. Check dnsmasq configuration:
   ```bash
   cat /etc/dnsmasq.conf.d/10-consul
   ```

4. Use the DNS resolver script:
   ```bash
   ./dns-resolver.sh
   ```

### Port Conflicts

If services fail due to port conflicts:

1. Check what's using the port:
   ```bash
   sudo lsof -i :<port>
   ```

2. Change the port in your configuration:
   ```bash
   # Edit config/custom.conf
   TRAEFIK_HTTP_PORT=81  # Change from default 80
   ```

3. Redeploy the affected service:
   ```bash
   ./scripts/04-deploy-traefik.sh
   ```

### Certificate Trust Issues

If browsers don't trust your certificates:

1. Export certificate from Synology:
   ```bash
   scp your-username@synology-ip:/volume1/nomad/config/certs/homelab.crt .
   ```

2. Import to your device:
   - Windows: Double-click and install to "Trusted Root Certification Authorities"
   - macOS: Double-click and add to Keychain, set to "Always Trust"
   - Linux: `sudo cp homelab.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates`
   - iOS/Android: Email the certificate to yourself and install profile

## Volume and Data Issues

### Volume Creation Failures

If volume creation fails:

1. Check Nomad server logs:
   ```bash
   journalctl -u nomad
   ```

2. Verify directory permissions:
   ```bash
   ls -la /volume1/nomad/volumes/
   ```

3. Try creating the volume manually:
   ```bash
   nomad volume create config/volumes.hcl
   ```

### Data Persistence

If data isn't persisting between restarts:

1. Verify volume mounts:
   ```bash
   ALLOC_ID=$(nomad job allocs -job <job-name> -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec ${ALLOC_ID} df -h
   ```

2. Check if volumes are being used correctly:
   ```bash
   nomad job inspect <job-name> | grep -A 10 volume
   ```

3. Ensure proper ownership:
   ```bash
   # For Grafana
   sudo chown -R 472:472 /volume1/nomad/volumes/standard/grafana_data
   ```

### Container Manager Issues

If you're experiencing issues with Synology's Container Manager:

1. Check Container Manager logs:
   ```bash
   sudo cat /var/log/messages | grep docker
   ```

2. Verify Docker storage space:
   ```bash
   df -h /var/packages/ContainerManager/var/docker
   ```

3. Clean up unused images:
   ```bash
   docker system prune -a
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
   DATA_DIR=/volume2/nomad/volumes  # Change to a different volume
   ```

## DSM-Specific Issues

### After DSM Updates

If you encounter issues after DSM updates:

1. Check if Nomad is still running:
   ```bash
   systemctl status nomad
   ```

2. Restart Nomad if needed:
   ```bash
   systemctl restart nomad
   ```

3. Restore Consul DNS configuration:
   ```bash
   sudo cp /volume1/nomad/config/10-consul /etc/dnsmasq.conf.d/
   sudo systemctl restart dnsmasq
   ```

4. Check service status:
   ```bash
   nomad job status
   ```

### Container Manager Problems

If Synology's Container Manager isn't working correctly:

1. Restart the package:
   ```bash
   synopkg restart ContainerManager
   ```

2. Check for conflicting Docker configurations:
   ```bash
   cat /var/packages/ContainerManager/etc/dockerd.json
   ```

3. Verify Docker daemon is running:
   ```bash
   ps aux | grep dockerd
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

### "Vault is sealed"

If you see "Vault is sealed" errors:

1. Check Vault status:
   ```bash
   VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec -task vault ${VAULT_ALLOC} vault status
   ```

2. Unseal Vault:
   ```bash
   nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key1>
   nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key2>
   nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key3>
   ```

### "Invalid token"

If you see "Invalid token" errors with Vault:

1. Check token validity:
   ```bash
   VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec -task vault ${VAULT_ALLOC} vault token lookup
   ```

2. Create a new token:
   ```bash
   nomad alloc exec -task vault ${VAULT_ALLOC} vault token create -policy=<policy-name>
   ```

### "Certificate has expired" or "Unknown Authority"

If you see certificate errors:

1. Check certificate expiration:
   ```bash
   openssl x509 -in /volume1/nomad/config/certs/homelab.crt -noout -dates
   ```

2. Regenerate certificates if needed:
   ```bash
   openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
     -keyout /volume1/nomad/config/certs/homelab.key \
     -out /volume1/nomad/config/certs/homelab.crt \
     -subj "/CN=*.homelab.local" \
     -addext "subjectAltName=DNS:*.homelab.local,DNS:homelab.local"
   ```

3. Restart Traefik:
   ```bash
   nomad job restart traefik
   ```

### "Invalid redirect URI"

If you see OIDC "Invalid redirect URI" errors:

1. Check client configuration in Keycloak:
   ```
   https://auth.homelab.local/auth/admin/
   ```

2. Verify the redirect URI being used:
   ```
   # Check browser network traffic during authentication
   ```

3. Update client configuration:
   ```
   # Add the correct redirect URI to the client in Keycloak
   ```

### "Failed to retrieve ACL token" in Nomad CLI

If you encounter ACL token issues with Nomad CLI:

1. Create a management token in the Nomad UI
2. Export the token:
   ```bash
   export NOMAD_TOKEN=<your-token>
   ```
3. Add to your .bashrc/.zshrc for persistence:
   ```bash
   echo 'export NOMAD_TOKEN=<your-token>' >> ~/.bashrc
   ```