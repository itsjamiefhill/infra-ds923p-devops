# 3. troubleshooting/services.md
# Service-Specific Troubleshooting

This document provides troubleshooting guidance for specific services in the HomeLab DevOps Platform.

## Table of Contents

1. [Consul](#consul)
2. [Traefik](#traefik)
3. [Vault](#vault)
4. [Docker Registry](#docker-registry)
5. [Monitoring Stack](#monitoring-stack)
6. [Logging Stack](#logging-stack)
7. [OIDC Authentication](#oidc-authentication)
8. [Homepage Dashboard](#homepage-dashboard)

## Consul

### Consul Not Starting

If Consul fails to start:

1. Check if the ports are already in use:
   ```bash
   ss -tulpn | grep 8500
   ```

2. Make sure the data directory is writable:
   ```bash
   sudo chmod 777 /volume1/docker/nomad/volumes/high_performance/consul_data
   ```

3. Check logs:
   ```bash
   sudo docker logs consul
   ```

### Multiple Private IPv4 Addresses Error

If you see this error in Consul logs:
```
==> Multiple private IPv4 addresses found. Please configure one with 'bind' and/or 'advertise'.
```

**Cause**:
Consul cannot automatically determine which network interface to use because your Synology has multiple IP addresses or network interfaces.

**Solution**:

1. Get your primary IP address:
   ```bash
   PRIMARY_IP=$(ip route get 1 | awk '{print $7;exit}' 2>/dev/null || hostname -I | awk '{print $1}')
   ```

2. Stop and remove the existing Consul container:
   ```bash
   sudo docker stop consul
   sudo docker rm consul
   ```

3. Start Consul with explicit bind and advertise addresses:
   ```bash
   sudo docker run -d --name consul \
     --restart always \
     --network host \
     -v ${DATA_DIR}/consul_data:/consul/data \
     hashicorp/consul:1.15.4 \
     agent -server -bootstrap \
     -bind=$PRIMARY_IP \
     -advertise=$PRIMARY_IP \
     -client=0.0.0.0 \
     -ui
   ```

4. Update the start-consul.sh script to include these parameters:
   ```bash
   # Edit the script
   nano ${PARENT_DIR}/bin/start-consul.sh
   
   # Update the docker run command to include bind and advertise parameters
   ```

### Consul UI Not Accessible

If you can't access the Consul UI:

1. Verify the container is running:
   ```bash
   sudo docker ps | grep consul
   ```

2. Check if direct access works:
   ```bash
   curl -I http://localhost:8500
   ```

3. Check docker logs for errors:
   ```bash
   sudo docker logs consul
   ```

4. Verify host entry if accessing via domain name:
   ```bash
   ping consul.homelab.local
   ```

### Docker vs Nomad Deployment Issues

If you're having issues deploying Consul as a Nomad job:

**Cause**:
The Synology version of Nomad may have limitations with container networking or volume management that affect Consul operation.

**Solution**:

1. Use direct Docker deployment instead:
   ```bash
   # Stop the Nomad-managed Consul job if it exists
   nomad job stop consul
   
   # Deploy using Docker directly
   sudo docker run -d --name consul \
     --restart always \
     --network host \
     -v ${DATA_DIR}/consul_data:/consul/data \
     hashicorp/consul:1.15.4 \
     agent -server -bootstrap \
     -bind=$(hostname -I | awk '{print $1}') \
     -advertise=$(hostname -I | awk '{print $1}') \
     -client=0.0.0.0 \
     -ui
   ```

2. Create helper scripts for management:
   ```bash
   # Create a start script
   echo '#!/bin/bash
   sudo docker stop consul 2>/dev/null || true
   sudo docker rm consul 2>/dev/null || true
   sudo docker run -d --name consul \
     --restart always \
     --network host \
     -v /volume1/docker/nomad/volumes/consul_data:/consul/data \
     hashicorp/consul:1.15.4 \
     agent -server -bootstrap \
     -bind=$(hostname -I | awk '"'"'{print $1}'"'"') \
     -advertise=$(hostname -I | awk '"'"'{print $1}'"'"') \
     -client=0.0.0.0 \
     -ui' > /volume1/docker/nomad/bin/start-consul.sh
   
   # Create a stop script
   echo '#!/bin/bash
   sudo docker stop consul
   sudo docker rm consul' > /volume1/docker/nomad/bin/stop-consul.sh
   
   # Make them executable
   chmod +x /volume1/docker/nomad/bin/start-consul.sh
   chmod +x /volume1/docker/nomad/bin/stop-consul.sh
   ```

### DNS Resolution Issues

If services cannot resolve `.consul` domains:

1. Direct Docker Method (most reliable):
   ```bash
   # Use Docker to test if Consul DNS is working
   sudo docker run --rm --network host alpine sh -c "apk add --no-cache bind-tools && dig @127.0.0.1 -p 8600 consul.service.consul"
   ```

2. For local resolution, add hosts file entries:
   ```bash
   # Add an entry for consul.service.consul
   sudo grep -q "consul.service.consul" /etc/hosts || \
     echo "$(hostname -I | awk '{print $1}') consul.service.consul" | sudo tee -a /etc/hosts
   ```

3. For specific services, add more hosts entries:
   ```bash
   echo "10.0.4.78 traefik.service.consul" | sudo tee -a /etc/hosts
   echo "10.0.4.78 vault.service.consul" | sudo tee -a /etc/hosts
   ```

## Traefik

### Traefik Not Routing

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

### Certificate Issues

If you're having TLS certificate issues:

1. Check certificate validity:
   ```bash
   openssl x509 -in /volume1/docker/nomad/config/certs/homelab.crt -text -noout
   ```

2. Verify certificate is mounted correctly:
   ```bash
   nomad alloc exec <traefik-alloc-id> ls -la /etc/traefik/certs
   ```

3. Import certificate to your client device:
   - Windows: Import to "Trusted Root Certification Authorities"
   - macOS: Import to Keychain, set to "Always Trust"
   - Linux: Add to `/usr/local/share/ca-certificates/` and run `update-ca-certificates`

## Vault

### Vault Sealed

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

### Vault Authentication Issues

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

### Secret Engines Issues

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

## Docker Registry

### Push/Pull Issues

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
   sudo cp /volume1/docker/nomad/config/certs/homelab.crt /etc/docker/certs.d/registry.homelab.local:5000/ca.crt

   # Restart Docker
   sudo systemctl restart docker
   ```

### Storage Issues

If the registry is having storage problems:

1. Check available space:
   ```bash
   df -h /volume1/docker/nomad/volumes/high_capacity/registry_data
   ```

2. Run garbage collection:
   ```bash
   REGISTRY_ALLOC=$(nomad job allocs -job docker-registry -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec -task registry ${REGISTRY_ALLOC} registry garbage-collect /etc/docker/registry/config.yml
   ```

## Monitoring Stack

### Prometheus Issues

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

### Grafana Issues

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
   ls -la /volume1/docker/nomad/volumes/standard/grafana_data
   sudo chown -R 472:472 /volume1/docker/nomad/volumes/standard/grafana_data
   ```

## Logging Stack

### Loki Issues

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

### Promtail Issues

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

## OIDC Authentication

### Keycloak Issues

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
   ls -la /volume1/docker/nomad/volumes/standard/keycloak_data
   ```

### OIDC Proxy Issues

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

### "Invalid redirect URI" Error

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

## Homepage Dashboard

### Dashboard Not Loading

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

### Service Discovery Issues

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