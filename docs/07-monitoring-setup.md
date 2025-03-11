# Monitoring Setup for Synology DS923+

This document provides detailed information about the monitoring stack of the HomeLab DevOps Platform for Synology DS923+.

## Overview

The monitoring stack consists of several components that work together to provide comprehensive visibility into the health, performance, and behavior of your platform:

- **Prometheus**: Time-series database for metrics collection and storage
- **Grafana**: Visualization platform for metrics and dashboards
- **Node Exporter**: System-level metrics collector
- **Service Exporters**: Metrics endpoints exposed by platform services

This monitoring stack enables you to:
- Track system resource utilization on your Synology DS923+
- Monitor service health and performance
- Set up alerts for critical conditions
- Visualize trends and patterns
- Troubleshoot issues effectively

## Architecture

The monitoring stack follows a standard architecture:

1. **Data Collection**: Node Exporter and service exporters collect metrics
2. **Storage**: Prometheus stores metrics as time-series data
3. **Visualization**: Grafana provides dashboards and visualizations
4. **Discovery**: Consul enables automatic discovery of metric endpoints

## Components

### Prometheus

Prometheus is the core of the monitoring stack:

- **Role**: Time-series database for metrics collection and storage
- **Scrape Interval**: 15 seconds (default)
- **Retention**: Local storage on high_performance volume
- **Service Discovery**: Uses Consul to find services to monitor
- **Configuration**: Auto-generated based on platform services

### Grafana

Grafana provides visualization for metrics:

- **Role**: Dashboard platform for metrics visualization
- **Authentication**: Integrated with OIDC for authentication
- **Datasources**: Pre-configured for Prometheus and Loki
- **Dashboards**: Pre-loaded system dashboards
- **Persistence**: Host volume for dashboard and configuration storage
- **Secrets**: Uses Vault for sensitive configuration

### Node Exporter

Node Exporter collects system-level metrics:

- **Role**: Collects host metrics (CPU, memory, disk, network, etc.)
- **Deployment**: Runs on the Synology NAS
- **Metrics Path**: `/metrics` endpoint exposed on port 9100
- **Integration**: Automatically discovered by Prometheus

## Configuration

### Prometheus Configuration

Prometheus is configured via a configuration file generated during installation:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'nomad'
    metrics_path: '/v1/metrics'
    params:
      format: ['prometheus']
    static_configs:
      - targets: ['{{ env "NOMAD_IP_http" }}:4646']

  - job_name: 'consul'
    consul_sd_configs:
      - server: 'consul.service.consul:8500'
        services: ['consul']

  - job_name: 'node-exporter'
    consul_sd_configs:
      - server: 'consul.service.consul:8500'
        services: ['node-exporter']

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'traefik'
    consul_sd_configs:
      - server: 'consul.service.consul:8500'
        services: ['traefik']
    metrics_path: '/metrics'
    
  - job_name: 'vault'
    metrics_path: '/v1/sys/metrics'
    params:
      format: ['prometheus']
    consul_sd_configs:
      - server: 'consul.service.consul:8500'
        services: ['vault']
```

### Grafana Configuration

Grafana is configured with:

1. **Datasources**: Prometheus and Loki pre-configured
2. **Dashboards**: System overview dashboard pre-loaded
3. **Authentication**: OIDC integration for user login
4. **Plugins**: Basic plugins pre-installed

### Vault Integration

Grafana uses Vault for storing sensitive configuration:

```hcl
# In Grafana job template
template {
  data = <<EOF
{{- with secret "kv/data/grafana/admin" }}
GF_SECURITY_ADMIN_USER={{ .Data.data.username }}
GF_SECURITY_ADMIN_PASSWORD={{ .Data.data.password }}
{{- end }}
EOF
  destination = "secrets/grafana.env"
  env = true
}
```

## Memory Optimization for Synology DS923+

With 32GB RAM available on your system, the monitoring stack is configured with generous resource allocation:

```hcl
# Prometheus resources
resources {
  cpu    = 1000  # 1 core
  memory = 4096  # 4 GB RAM
}

# Grafana resources
resources {
  cpu    = 500   # 0.5 cores
  memory = 1024  # 1 GB RAM
}

# Node Exporter resources
resources {
  cpu    = 100   # 0.1 cores
  memory = 128   # 128 MB RAM
}
```

These allocations provide excellent performance for your monitoring stack while still leaving ample resources for other services.

## Data Persistence

Both Prometheus and Grafana use Nomad volumes for data persistence:

- **prometheus_data**: Stored in high_performance volume
- **grafana_data**: Stored in standard volume with specific user permissions (UID 472)

## Technical Implementation

### Prometheus Job

Prometheus is deployed as a Nomad job:

```hcl
job "prometheus" {
  datacenters = ["dc1"]
  type = "service"

  group "monitoring" {
    count = 1
    
    volume "prometheus_data" {
      type = "host"
      read_only = false
      source = "high_performance"
    }

    task "prometheus" {
      driver = "docker"
      
      volume_mount {
        volume = "prometheus_data"
        destination = "/prometheus"
        read_only = false
      }

      config {
        image = "prom/prometheus:latest"
        ports = ["http"]
        
        volumes = [
          "local/prometheus.yml:/etc/prometheus/prometheus.yml"
        ]
      }

      template {
        data = <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'nomad'
    metrics_path: '/v1/metrics'
    params:
      format: ['prometheus']
    static_configs:
      - targets: ['{{ env "NOMAD_IP_http" }}:4646']

  # Additional scrape configs...
EOF
        destination = "local/prometheus.yml"
      }

      resources {
        cpu    = 1000
        memory = 4096
      }

      service {
        name = "prometheus"
        port = "http"
        
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.prometheus.rule=Host(`prometheus.homelab.local`)",
          "traefik.http.routers.prometheus.tls=true",
          "traefik.http.routers.prometheus.middlewares=oidc-auth@consul",
          "homepage.name=Prometheus",
          "homepage.icon=prometheus.png",
          "homepage.group=Monitoring",
          "homepage.description=Metrics collection and alerting"
        ]
      }
    }

    network {
      port "http" {
        static = 9090
      }
    }
  }
}
```

### Grafana Job

Grafana is deployed as a Nomad job:

```hcl
job "grafana" {
  datacenters = ["dc1"]
  type = "service"

  group "visualization" {
    count = 1
    
    volume "grafana_data" {
      type = "host"
      read_only = false
      source = "standard"
    }

    task "grafana" {
      driver = "docker"
      
      volume_mount {
        volume = "grafana_data"
        destination = "/var/lib/grafana"
        read_only = false
      }

      config {
        image = "grafana/grafana:latest"
        ports = ["http"]
        
        volumes = [
          "local/datasources:/etc/grafana/provisioning/datasources",
          "local/dashboards:/etc/grafana/provisioning/dashboards"
        ]
      }
      
      # Vault integration for admin credentials
      template {
        data = <<EOF
{{- with secret "kv/data/grafana/admin" }}
GF_SECURITY_ADMIN_USER={{ .Data.data.username }}
GF_SECURITY_ADMIN_PASSWORD={{ .Data.data.password }}
{{- end }}
EOF
        destination = "secrets/grafana.env"
        env = true
      }

      # Datasource configuration
      template {
        data = <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus.service.consul:9090
    isDefault: true
  - name: Loki
    type: loki
    access: proxy
    url: http://loki.service.consul:3100
EOF
        destination = "local/datasources/prometheus.yml"
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      service {
        name = "grafana"
        port = "http"
        
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.grafana.rule=Host(`grafana.homelab.local`)",
          "traefik.http.routers.grafana.tls=true",
          "homepage.name=Grafana",
          "homepage.icon=grafana.png",
          "homepage.group=Monitoring",
          "homepage.description=Metrics visualization and dashboards"
        ]
      }
    }

    network {
      port "http" {
        static = 3000
      }
    }
  }
}
```

### Node Exporter Job

Node Exporter is deployed as a system job:

```hcl
job "node-exporter" {
  datacenters = ["dc1"]
  type = "system"

  group "metrics" {
    task "node-exporter" {
      driver = "docker"
      
      config {
        image = "prom/node-exporter:latest"
        network_mode = "host"
        
        args = [
          "--path.procfs=/host/proc",
          "--path.sysfs=/host/sys"
        ]
        
        volumes = [
          "/proc:/host/proc:ro",
          "/sys:/host/sys:ro"
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }

      service {
        name = "node-exporter"
        port = "9100"
      }
    }
  }
}
```

## Accessing the Monitoring Stack

### Prometheus UI

Access the Prometheus web interface at:
- `https://prometheus.homelab.local`
- Authentication handled by OIDC integration

The Prometheus UI allows you to:
- Query metrics using PromQL
- View targets and their health
- Explore metric data
- Check alert status (if configured)

### Grafana Dashboards

Access Grafana at:
- `https://grafana.homelab.local`
- Authentication handled by OIDC integration

## Default Dashboards

The monitoring stack comes with pre-configured dashboards:

1. **Synology System Overview**: Shows CPU, memory, disk, and network metrics specific to your DS923+
2. **Node Exporter**: Detailed system metrics for your Synology NAS
3. **Prometheus Stats**: Metrics about Prometheus itself
4. **Traefik Dashboard**: Metrics for Traefik proxy
5. **Consul Dashboard**: Service discovery health and metrics
6. **Vault Dashboard**: Secrets engine metrics and operations

## Adding Custom Dashboards

To add custom dashboards:

1. Log in to Grafana
2. Click "Create" or "+" icon
3. Select "Dashboard"
4. Add panels using the Prometheus data source
5. Save the dashboard

You can also import dashboards from the Grafana dashboard repository using the dashboard ID.

## Metrics Collection

### Default Metrics

The monitoring stack collects:

1. **System Metrics**:
   - CPU usage and load
   - Memory usage
   - Disk usage and I/O
   - Network traffic
   - System uptime

2. **Service Metrics**:
   - Nomad job and task metrics
   - Consul service health
   - Traefik request metrics
   - Vault operation metrics
   - Other service-specific metrics

### Synology-Specific Metrics

For the DS923+, additional metrics are collected:

- RAID status and health
- Disk temperatures
- Fan speeds
- UPS status (if connected)
- Volume utilization

### Adding Custom Metrics

To expose custom metrics from your applications:

1. Implement a Prometheus client library in your application
2. Expose metrics on a `/metrics` endpoint
3. Register your service in Consul with appropriate metadata
4. Prometheus will automatically discover and scrape your service

## Alerts

The monitoring stack includes alerting capabilities:

```yaml
# In prometheus.yml
alerting:
  alertmanagers:
  - static_configs:
    - targets:
      - alertmanager:9093

rule_files:
  - "/etc/prometheus/rules/*.yml"
```

Alert rules are defined in separate files:

```yaml
# In /etc/prometheus/rules/system.yml
groups:
- name: system
  rules:
  - alert: HighCPULoad
    expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High CPU load (instance {{ $labels.instance }})"
      description: "CPU load is > 80%\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
```

## Handling DSM Updates

When updating your Synology DSM:

1. The monitoring services will typically stop during the update
2. Metrics data will remain safe in the persistent volumes
3. After the update, the services will restart automatically
4. Some historical data points during the update period will be missing

## Integration with Logging

The monitoring stack is designed to work with the logging stack:

- Grafana can display both metrics and logs
- Loki datasource is pre-configured in Grafana
- You can create dashboards that combine metrics and logs

For more information, see [Logging Setup](08-logging-setup.md).

## Backup and Recovery

### Backing Up Monitoring Data

To backup Prometheus and Grafana data:

```bash
# Option 1: Using Synology Hyper Backup
# Include these directories in your backup task:
# - /volume1/docker/nomad/volumes/high_performance/prometheus_data
# - /volume1/docker/nomad/volumes/standard/grafana_data

# Option 2: Manual backup
# Stop services
nomad job stop grafana
nomad job stop prometheus

# Backup data
tar -czf /volume2/backups/services/monitoring_backup.tar.gz \
  -C /volume1/docker/nomad/volumes/high_performance prometheus_data \
  -C /volume1/docker/nomad/volumes/standard grafana_data

# Restart services
nomad job run jobs/prometheus.hcl
nomad job run jobs/grafana.hcl
```

### Restoring Monitoring Data

To restore monitoring data:

```bash
# Stop services
nomad job stop grafana
nomad job stop prometheus

# Restore data
tar -xzf /volume2/backups/services/monitoring_backup.tar.gz -C /volume1/docker/nomad/volumes

# Fix permissions
chown -R 472:472 /volume1/docker/nomad/volumes/standard/grafana_data

# Restart services
nomad job run jobs/prometheus.hcl
nomad job run jobs/grafana.hcl
```

## Troubleshooting

### Common Prometheus Issues

1. **Target Scraping Failures**:
   - Check if the target is up and exposing metrics
   - Verify network connectivity to the target
   - Ensure the target is registered in Consul correctly

2. **Data Storage Issues**:
   - Check disk space on the Prometheus volume
   - Verify permissions on the data directory
   - Adjust retention settings if needed

### Common Grafana Issues

1. **Dashboard Loading Issues**:
   - Check Grafana logs: `nomad alloc logs <grafana-alloc-id>`
   - Verify Prometheus data source is working
   - Test queries directly in Prometheus UI

2. **Authentication Problems**:
   - Check OIDC configuration
   - Verify redirect URIs are correct
   - Inspect browser console for auth flow errors

## Next Steps

After deploying the monitoring stack, the next step is to set up the logging stack. This is covered in [Logging Setup](08-logging-setup.md).