# Consul Setup for Synology DS923+

This document provides detailed information about the Consul service discovery component of the HomeLab DevOps Platform on Synology DS923+.

## Overview

Consul is a service mesh solution that enables service discovery, configuration, and segmentation functionality for the platform. It acts as the backbone for service-to-service communication and provides key-value storage for configuration.

In the HomeLab DevOps Platform, Consul is the first service deployed because other components depend on it for:
- Service discovery
- Health checking
- DNS resolution
- Key-value storage
- Service metadata for the Homepage dashboard

## Architecture

The platform implements Consul in a simplified single-server mode appropriate for a Synology homelab environment:

- **Deployment Mode**: Single server with `-bootstrap` mode
- **Service Registration**: All platform services register with Consul
- **DNS Interface**: Provides service.consul domain resolution
- **UI**: Web interface for service management
- **Metadata**: Stores service metadata for Homepage dashboard integration

## Synology-Specific Deployment Method

Due to challenges with Nomad on Synology devices, Consul is deployed directly as a Docker container rather than as a Nomad job. This provides greater control and reliability for this critical service.

### Direct Docker Deployment

The `03-deploy-consul.sh` script creates and uses helper scripts to manage the Consul container:

1. **Helper Scripts**:
   - `bin/start-consul.sh`: Script to start the Consul container
   - `bin/stop-consul.sh`: Script to stop the Consul container

2. **Container Configuration**:
   ```bash
   sudo docker run -d --name consul \
     --restart always \
     --network host \
     -v ${DATA_DIR}/consul_data:/consul/data \
     hashicorp/consul:${CONSUL_VERSION} \
     agent -server -bootstrap \
     -bind=${PRIMARY_IP} \
     -advertise=${PRIMARY_IP} \
     -client=0.0.0.0 \
     -ui
   ```

3. **Network Mode**:
   - Uses `--network host` to share the host's network stack
   - Avoids port mapping and network isolation issues

4. **IP Configuration**:
   - Explicitly sets `-bind` and `-advertise` parameters to handle multiple network interfaces
   - Uses a primary IP detection mechanism to find the correct interface

5. **Automatic Startup**:
   - Instructions for creating a Synology Task Scheduler entry to auto-start Consul on boot

### Reference Configuration

The deployment creates a reference file at `$JOB_DIR/consul.reference` with information about the Consul deployment:
```
# Note: Consul was deployed directly as a Docker container
# To restart: sudo ${PARENT_DIR}/bin/stop-consul.sh && sudo ${PARENT_DIR}/bin/start-consul.sh
# To stop: sudo ${PARENT_DIR}/bin/stop-consul.sh
# To view logs: sudo docker logs consul
# Container name: consul
# IP address: ${PRIMARY_IP}
```

## Configuration

Key configuration elements for Consul include:

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| HTTP Port | 8500 | Web UI and API |
| DNS Port | 8600 | DNS interface for service discovery |
| Server Port | 8300 | Server RPC |
| Serf LAN Port | 8301 | Gossip protocol for LAN |
| Serf WAN Port | 8302 | Gossip protocol for WAN |
| Bootstrap | true | Self-elect as cluster leader |
| UI | enabled | Web interface available |
| Bind Address | AUTO | IP address to bind services to |
| Advertise Address | AUTO | IP address to advertise to other nodes |

## Data Persistence

Consul data is persisted on the Synology NAS using a mapped Docker volume:
- **Host Path**: `/volume1/docker/nomad/volumes/consul_data` (default)
- **Container Path**: `/consul/data`

This ensures that Consul's state, including service registrations and key-value pairs, is maintained across restarts and DSM updates.

## DNS Integration on Synology

### Hosts File Method

Since Synology DSM doesn't use dnsmasq by default for DNS resolution, the most reliable method for DNS integration is to add an entry to the `/etc/hosts` file:

```bash
# Add consul.service.consul to hosts file
PRIMARY_IP=$(get_primary_ip)
sudo sed -i '/consul\.service\.consul/d' /etc/hosts  # Remove any existing entry
echo "${PRIMARY_IP} consul.service.consul" | sudo tee -a /etc/hosts
```

This allows local resolution of the `consul.service.consul` domain on the Synology device itself.

### Optional dnsmasq Configuration

If dnsmasq is available and configured on your Synology, you can also set up forwarding of .consul domains:

```bash
# If dnsmasq is available
if command -v dnsmasq &>/dev/null; then
  sudo mkdir -p /etc/dnsmasq.conf.d
  echo "server=/consul/127.0.0.1#8600" | sudo tee /etc/dnsmasq.conf.d/10-consul
  # Attempt to restart dnsmasq (may not work on all Synology models)
  sudo systemctl restart dnsmasq 2>/dev/null || true
fi
```

### Network-Wide DNS Resolution

For network-wide resolution of `.consul` domains, consider one of these approaches:

1. **Router DNS Configuration**:
   - Add DNS forwarding in your router to send `.consul` domains to your Synology IP
   - Configure conditional forwarding for the `.consul` domain

2. **Host Entries on Clients**:
   - Add entries to `/etc/hosts` (or equivalent) on client machines

3. **Local DNS Server**:
   - Run a dedicated DNS server with proper forwarding rules
   - Configure clients to use this DNS server

## Service Registration

Other services in the platform register themselves with Consul, enabling:

1. **Service Discovery**: Services can find each other by name
2. **Health Checking**: Consul monitors service health
3. **DNS Resolution**: Services are accessible via DNS (service.service.consul)
4. **Metadata Exchange**: Services can advertise capabilities through tags
5. **Homepage Integration**: Services provide display metadata for the dashboard

For example, this is how Traefik discovers services to route:

```hcl
[providers.consulCatalog]
  prefix = "traefik"
  exposedByDefault = false
  
  [providers.consulCatalog.endpoint]
    address = "127.0.0.1:8500"
    scheme = "http"
```

## Homepage Dashboard Integration

For the Homepage dashboard, services register with additional metadata:

```hcl
service {
  name = "grafana"
  port = "http"
  
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.grafana.rule=Host(`grafana.homelab.local`)",
    "homepage.name=Grafana",
    "homepage.icon=grafana.png",
    "homepage.group=Monitoring",
    "homepage.description=Metrics and dashboard visualization"
  ]
}
```

These tags allow Homepage to automatically discover and categorize services for display.

## Accessing Consul

You can access Consul through multiple interfaces:

1. **Web UI**: `http://consul.homelab.local` or `http://your-synology-ip:8500`
2. **HTTP API**: `http://your-synology-ip:8500/v1/...`
3. **DNS Interface**: Direct query to consul DNS `dig @127.0.0.1 -p 8600 <service>.service.consul`
4. **Command Line**: Using the Consul CLI (if installed)
5. **Host Entry**: If you've added the hosts file entry, simply `http://consul.service.consul:8500`

## Memory Optimization for Synology

Since the DS923+ has 32GB RAM, you can optimize Consul's memory usage:

```bash
# In your custom.conf file:
CONSUL_MEMORY=1024  # 1GB RAM
```

This provides ample memory for Consul while leaving resources for other services.

## Security Considerations

The default setup is optimized for ease of use in a homelab environment. For enhanced security:

1. **Integration with Vault**: Configure Consul to use Vault for secret storage
2. **Enable ACLs**: Configure access control lists
3. **Enable TLS**: Secure communications with certificates
4. **Set Agent Tokens**: Use tokens for agent communications

To implement these enhancements, add the appropriate configuration to your `custom.conf` file.

## Scaling Considerations

While the default setup uses a single Consul server, you can scale to a multi-server cluster if needed in the future:

1. Modify the container deployment to join existing servers
2. Set appropriate bootstrap settings
3. Configure retry_join for server discovery

For most Synology homelab setups, a single server is sufficient.

## Key Consul Commands

Useful Consul commands for administration:

- **View Consul logs**: `sudo docker logs consul`
- **Restart Consul**: `sudo ${SCRIPT_DIR}/bin/stop-consul.sh && sudo ${SCRIPT_DIR}/bin/start-consul.sh`
- **List services**: `curl http://localhost:8500/v1/catalog/services`
- **View nodes**: `curl http://localhost:8500/v1/catalog/nodes`
- **Check service health**: `curl http://localhost:8500/v1/health/service/<service-name>`
- **List KV pairs**: `curl http://localhost:8500/v1/kv/?recurse`
- **Store KV pair**: `curl -X PUT -d '<value>' http://localhost:8500/v1/kv/<key>`

## Monitoring Consul

Consul's status can be monitored through:

1. **Prometheus**: Configured to scrape Consul metrics
2. **Grafana**: Dashboards available for visualizing metrics
3. **Consul UI**: Real-time status of services and nodes
4. **Docker logs**: `sudo docker logs consul`
5. **Homepage Dashboard**: High-level status display

## Handling DSM Updates

When updating your Synology DSM:

1. Consul should restart automatically due to the `--restart always` flag
2. Data will persist in the mapped volume
3. After an update, verify hosts file integration still works:
   ```bash
   # If hosts file entry is missing, restore it
   echo "10.0.4.78 consul.service.consul" | sudo tee -a /etc/hosts
   ```

4. Verify Consul is running:
   ```bash
   sudo docker ps | grep consul
   ```

5. If needed, restart Consul:
   ```bash
   sudo ${SCRIPT_DIR}/bin/stop-consul.sh && sudo ${SCRIPT_DIR}/bin/start-consul.sh
   ```

## Using Consul in Your Applications

You can leverage Consul from your own applications deployed to the platform:

1. **Service Registration**: Register your service with Consul
2. **Service Discovery**: Look up other services by name
3. **Key-Value Storage**: Store and retrieve configuration
4. **Health Checking**: Register health checks for your service
5. **Homepage Integration**: Add metadata for dashboard display

## Troubleshooting

Common issues and their solutions:

1. **Consul Not Starting**:
   - Check logs: `sudo docker logs consul`
   - Verify data directory permissions
   - Ensure ports are available

2. **Multiple Private IPv4 Addresses Found**:
   - Problem: Consul cannot determine which network interface to use
   - Solution: Explicitly set bind and advertise parameters:
     ```bash
     # Get your primary IP
     PRIMARY_IP=$(ip route get 1 | awk '{print $7;exit}')
     
     # Start Consul with explicit binding
     sudo docker run -d --name consul \
       --restart always \
       --network host \
       -v ${DATA_DIR}/consul_data:/consul/data \
       hashicorp/consul:${CONSUL_VERSION} \
       agent -server -bootstrap \
       -bind=${PRIMARY_IP} \
       -advertise=${PRIMARY_IP} \
       -client=0.0.0.0 \
       -ui
     ```

3. **Services Not Registering**:
   - Check if services have Consul service blocks
   - Verify network connectivity between services and Consul
   - Inspect service tags and configuration

4. **DNS Resolution Failures**:
   - Verify hosts file entry: `cat /etc/hosts | grep consul`
   - Test direct query to Consul: `curl -v http://consul.service.consul:8500/ui/`
   - Test direct DNS query: `dig @127.0.0.1 -p 8600 consul.service.consul`
   - Use alternative DNS testing methods on Synology:
     ```bash
     # Using Docker for DNS testing
     sudo docker run --rm --network host alpine sh -c "apk add --no-cache bind-tools && dig @127.0.0.1 -p 8600 consul.service.consul"
     ```

5. **UI Not Accessible**:
   - Verify Consul is running: `sudo docker ps | grep consul`
   - Check direct IP access: `curl -v http://localhost:8500/ui/`
   - Check if hosts file resolution works: `ping consul.service.consul`

## Next Steps

After deploying Consul, the next step is to set up Traefik for reverse proxy functionality. This is covered in [Traefik Setup](04-traefik-setup.md).