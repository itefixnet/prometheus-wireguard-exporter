# WireGuard Prometheus Exporter

A lightweight, bash-based Prometheus exporter for WireGuard VPN statistics. This exporter uses only bash and socat to provide comprehensive WireGuard metrics for monitoring with Prometheus and Grafana.

## Features

- **Pure Bash Implementation**: No external dependencies except `socat` and `wireguard-tools`
- **Comprehensive Metrics**: Exports WireGuard statistics including:
  - Interface status and configuration
  - Per-peer connection status
  - Latest handshake timestamps
  - Data transfer statistics (bytes sent/received)
  - Peer endpoint information
  - Persistent keepalive settings
  - Allowed IP ranges count
- **Multi-Interface Support**: Monitor all WireGuard interfaces or specific ones
- **Docker Container Support**: Monitor WireGuard running in Docker containers
- **HTTP Server**: Built-in HTTP server using socat for serving metrics
- **Systemd Integration**: Ready-to-use systemd service file
- **Security**: Runs with minimal privileges using Linux capabilities
- **Auto-Discovery**: Automatically detects all WireGuard interfaces

## Quick Start

### Prerequisites

- WireGuard installed and configured
- `wireguard-tools` package installed
- `socat` package installed
- Prometheus server for scraping metrics
- Grafana (optional, for visualization)
- Root access or CAP_NET_ADMIN capability

### Basic Installation

1. Clone the repository:
```bash
git clone https://github.com/itefixnet/prometheus-wireguard-exporter.git
cd prometheus-wireguard-exporter
```

2. Make scripts executable:
```bash
chmod +x *.sh
```

3. Test the exporter:
```bash
sudo ./wireguard-exporter.sh test
```

4. Start the HTTP server:
```bash
sudo ./http-server.sh start
```

5. Access metrics at `http://localhost:9586/metrics`

### System Installation

For production deployment, install as a system service:

```bash
# Create user and directories
sudo useradd -r -s /bin/false wireguard-exporter
sudo mkdir -p /opt/wireguard-exporter
sudo mkdir -p /var/lib/wireguard-exporter

# Copy files
sudo cp *.sh /opt/wireguard-exporter/
sudo cp config.sh /opt/wireguard-exporter/
sudo cp wireguard-exporter.conf /opt/wireguard-exporter/
sudo cp wireguard-exporter.service /etc/systemd/system/

# Set permissions
sudo chown -R wireguard-exporter:wireguard-exporter /opt/wireguard-exporter
sudo chown -R wireguard-exporter:wireguard-exporter /var/lib/wireguard-exporter
sudo chmod +x /opt/wireguard-exporter/*.sh

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable wireguard-exporter
sudo systemctl start wireguard-exporter

# Check status
sudo systemctl status wireguard-exporter
```

## Configuration

### Environment Variables

The exporter can be configured using environment variables or configuration files:

| Variable | Default | Description |
|----------|---------|-------------|
| `WIREGUARD_INTERFACE` | (empty - all) | Specific interface to monitor, or empty for all |
| `WIREGUARD_DOCKER_CONTAINER` | (empty) | Docker container name if WireGuard runs in a container |
| `LISTEN_PORT` | `9586` | HTTP server port |
| `LISTEN_ADDRESS` | `0.0.0.0` | HTTP server bind address |
| `METRICS_PREFIX` | `wireguard` | Prometheus metrics prefix |
| `MAX_CONNECTIONS` | `10` | Maximum concurrent HTTP connections |
| `TIMEOUT` | `30` | Request timeout in seconds |

### Configuration Files

1. **`config.sh`**: Shell configuration file (sourced by scripts)
2. **`wireguard-exporter.conf`**: Systemd environment file

Example configuration to monitor a specific interface:
```bash
# In config.sh or wireguard-exporter.conf
WIREGUARD_INTERFACE=wg0
LISTEN_PORT=9586
```

### Monitoring WireGuard in Docker Containers

If WireGuard is running inside a Docker container, you can monitor it from the host by specifying the container name:

```bash
# Set the container name
export WIREGUARD_DOCKER_CONTAINER=wireguard

# Test connectivity
sudo ./wireguard-exporter.sh test

# Start the exporter (runs on host, monitors container)
./http-server.sh start
```

**How it works:**
- The exporter uses `docker exec <container> wg show` instead of `wg show`
- No need to install the exporter inside the container
- Exporter runs on the host with access to Docker socket
- Requires Docker to be installed on the host

**Configuration example:**
```bash
# In config.sh
export WIREGUARD_DOCKER_CONTAINER="wireguard"  # Your container name
export WIREGUARD_INTERFACE="wg0"               # Optional: specific interface
```

**Requirements:**
- Docker installed on the host
- Container must be running
- `wg` command available in the container
- User running exporter must have Docker permissions

**Finding your container name:**
```bash
# List running containers
docker ps --format '{{.Names}}'

# Test if wg is available in container
docker exec <container-name> wg show
```

## Metrics

The exporter provides comprehensive WireGuard VPN metrics:

### Version Information
- `wireguard_version_info{version="..."}` - WireGuard version information with label

### Interface Metrics
- `wireguard_interfaces_total` - Total number of WireGuard interfaces
- `wireguard_interface_up{interface="wg0"}` - Interface status (1=up, 0=down)
- `wireguard_interface_listen_port{interface="wg0"}` - Interface listen port
- `wireguard_interface_peers{interface="wg0"}` - Number of peers configured on interface

### Peer Metrics
- `wireguard_peer_connected{interface="wg0",public_key="abc12345",endpoint="1.2.3.4:51820"}` - Peer connection status (1=connected, 0=disconnected)
  - Connected is defined as a handshake within the last 3 minutes (180 seconds)
- `wireguard_peer_latest_handshake_seconds{interface="wg0",public_key="abc12345",endpoint="1.2.3.4:51820"}` - UNIX timestamp of the last handshake (gauge)
- `wireguard_peer_receive_bytes_total{interface="wg0",public_key="abc12345",endpoint="1.2.3.4:51820"}` - Total bytes received from peer (counter)
- `wireguard_peer_transmit_bytes_total{interface="wg0",public_key="abc12345",endpoint="1.2.3.4:51820"}` - Total bytes transmitted to peer (counter)
- `wireguard_peer_persistent_keepalive_interval{interface="wg0",public_key="abc12345",endpoint="1.2.3.4:51820"}` - Persistent keepalive interval in seconds
- `wireguard_peer_allowed_ips_count{interface="wg0",public_key="abc12345",endpoint="1.2.3.4:51820"}` - Number of allowed IP ranges for peer

**Note**: The `public_key` label shows the first 8 characters of the peer's public key for readability and security.

## Usage Examples

### Manual Testing

```bash
# Test WireGuard configuration
sudo ./wireguard-exporter.sh test

# Collect metrics once
sudo ./wireguard-exporter.sh collect

# Start HTTP server manually
sudo ./http-server.sh start

# Test HTTP endpoints
curl http://localhost:9586/metrics
curl http://localhost:9586/health
curl http://localhost:9586/
```

**Monitoring WireGuard in Docker Container:**

```bash
# Set container name
export WIREGUARD_DOCKER_CONTAINER=wireguard

# Test (no sudo needed if your user is in docker group)
./wireguard-exporter.sh test

# Collect metrics from container
./wireguard-exporter.sh collect

# Start HTTP server
./http-server.sh start
```

### Prometheus Configuration

Add a job to your `prometheus.yml`:

```yaml
scrape_configs:
  # Single instance
  - job_name: 'wireguard-exporter'
    static_configs:
      - targets: ['localhost:9586']
    scrape_interval: 30s
    metrics_path: /metrics
    
  # Multiple instances with labels
  - job_name: 'wireguard-servers'
    static_configs:
      - targets: ['vpn1.example.com:9586', 'vpn2.example.com:9586']
        labels:
          environment: 'production'
          datacenter: 'dc1'
      - targets: ['vpn-staging.example.com:9586']
        labels:
          environment: 'staging'
    scrape_interval: 30s
    metrics_path: /metrics
```

## Grafana Dashboard

A pre-built Grafana dashboard is included in `grafana-dashboard.json` with panels for:

- **Interface Status**: Real-time up/down status
- **Total Peers**: Number of configured peers
- **Listen Port**: Interface configuration
- **Time Since Last Handshake**: Connection freshness with color thresholds
- **Peer Traffic Rate**: Real-time bandwidth usage per peer (upload/download)
- **Peer Traffic Total**: Cumulative data transferred
- **Peer Details Table**: Comprehensive peer information with endpoints, allowed IPs, and statistics

### Import Dashboard

1. Open Grafana web interface
2. Go to **Dashboards** → **Import**
3. Upload `grafana-dashboard.json` or paste its contents
4. Select your Prometheus datasource
5. Click **Import**

The dashboard includes template variables for filtering by:
- **Instance**: Select specific exporter instances
- **Interface**: Filter by WireGuard interface (wg0, wg1, etc.)
- **Peer**: View specific peers or all

### Example Grafana Queries

```promql
# Active WireGuard peers
sum(wireguard_peer_connected)

# Peer bandwidth (bytes/sec)
rate(wireguard_peer_transmit_bytes_total[5m])
rate(wireguard_peer_receive_bytes_total[5m])

# Time since last handshake
time() - wireguard_peer_latest_handshake_seconds

# Peers with stale handshakes (> 5 minutes)
(time() - wireguard_peer_latest_handshake_seconds) > 300

# Total data transferred per interface
sum by (interface) (wireguard_peer_transmit_bytes_total)
sum by (interface) (wireguard_peer_receive_bytes_total)

# Peer connection status
wireguard_peer_connected{interface="wg0"}
```

## Troubleshooting

### Common Issues

1. **Permission Denied**:
   - Ensure scripts are executable: `chmod +x *.sh`
   - WireGuard stats require root or CAP_NET_ADMIN capability
   - Run with sudo: `sudo ./wireguard-exporter.sh test`

2. **Cannot Execute 'wg show'**:
   - Install wireguard-tools: `sudo apt-get install wireguard-tools` (Ubuntu/Debian)
   - Verify WireGuard is installed: `wg --version`
   - Check user has proper permissions

3. **No Interfaces Found**:
   - Verify WireGuard interfaces are up: `sudo wg show`
   - Check interface configuration: `sudo wg show all`
   - Ensure WireGuard service is running: `systemctl status wg-quick@wg0`

4. **Port Already in Use**:
   - Change `LISTEN_PORT` in configuration
   - Check for other services: `netstat -tlnp | grep 9586`

5. **Missing Dependencies**:
   ```bash
   # Install socat (Ubuntu/Debian)
   sudo apt-get install socat wireguard-tools
   
   # Install socat (CentOS/RHEL)
   sudo yum install socat wireguard-tools
   ```

6. **Docker Container Issues**:
   - **Container not found**: Verify container name with `docker ps --format '{{.Names}}'`
   - **Permission denied**: Add your user to docker group: `sudo usermod -aG docker $USER`
   - **wg command not in container**: Ensure wireguard-tools is installed in the container
   - **Cannot connect to Docker daemon**: Check Docker service: `sudo systemctl status docker`
   
   ```bash
   # Debug Docker container
   docker ps | grep wireguard
   docker exec <container> wg show
   docker exec <container> which wg
   
   # Check exporter can access container
   WIREGUARD_DOCKER_CONTAINER=<container> ./wireguard-exporter.sh test
   ```

### Logging

- Service logs: `journalctl -u wireguard-exporter -f`
- Manual logs: Scripts output to stderr

### Security Considerations

The exporter requires CAP_NET_ADMIN capability to read WireGuard statistics. The systemd service is configured to run with minimal privileges:
- Uses a dedicated user account
- Drops all capabilities except CAP_NET_ADMIN
- Restricts filesystem access
- Runs in a protected system environment

## Development

### Testing

```bash
# Run basic tests
sudo ./wireguard-exporter.sh test
sudo ./http-server.sh test

# Test with specific interface
WIREGUARD_INTERFACE=wg0 sudo ./wireguard-exporter.sh test

# Test metrics collection
sudo ./wireguard-exporter.sh collect | head -50
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Test thoroughly
4. Submit a pull request

### License

This project is licensed under the BSD 2-Clause License - see the [LICENSE](LICENSE) file for details.

## Support

- GitHub Issues: [https://github.com/itefixnet/prometheus-wireguard-exporter/issues](https://github.com/itefixnet/prometheus-wireguard-exporter/issues)
- Documentation: This README and inline script comments

## Alternatives

This exporter focuses on simplicity and minimal dependencies. For more advanced features, consider:
- [prometheus_wireguard_exporter](https://github.com/MindFlavor/prometheus_wireguard_exporter) (Rust-based)
- [wireguard-exporter](https://github.com/mdlayher/wireguard_exporter) (Go-based)
- Custom telegraf configurations

## Credits

Inspired by the [prometheus-dovecot-exporter](https://github.com/itefixnet/prometheus-dovecot-exporter) project.

## Related Projects

- [prometheus-dovecot-exporter](https://github.com/itefixnet/prometheus-dovecot-exporter) - Dovecot mail server exporter
- [prometheus-postfix-exporter](https://github.com/itefixnet/prometheus-postfix-exporter) - Postfix mail server exporter
- [prometheus-apache2-exporter](https://github.com/itefixnet/prometheus-apache2-exporter) - Apache HTTP server exporter

## Architecture

The exporter uses the `wg show` command to collect WireGuard statistics:
- Discovers all WireGuard interfaces automatically (or monitors specific ones)
- Parses `wg show dump` output for efficient data collection
- Exposes metrics via HTTP using socat
- Provides health check endpoint for monitoring
- Uses minimal system resources

## Metric Labels

Each peer metric includes labels for filtering and grouping:
- `interface`: WireGuard interface name (e.g., `wg0`)
- `public_key`: First 8 characters of peer's public key (e.g., `abc12345`)
- `endpoint`: Peer's endpoint address (e.g., `1.2.3.4:51820` or `(none)` if not established)

This labeling allows you to:
- Monitor specific peers across multiple servers
- Track bandwidth per peer
- Alert on disconnected peers
- Analyze traffic patterns by endpoint