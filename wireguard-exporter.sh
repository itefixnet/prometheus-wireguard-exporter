#!/bin/bash
#
# WireGuard Prometheus Exporter
# A bash-based exporter for WireGuard VPN statistics
#

# Set strict error handling
set -euo pipefail

# Source configuration if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Default configuration
WIREGUARD_INTERFACE="${WIREGUARD_INTERFACE:-}"
WIREGUARD_DOCKER_CONTAINER="${WIREGUARD_DOCKER_CONTAINER:-}"  # Docker container name (if WireGuard runs in container)
METRICS_PREFIX="${METRICS_PREFIX:-wireguard}"
STATE_FILE="${STATE_FILE:-/var/lib/wireguard-exporter/state}"
CACHE_TTL="${CACHE_TTL:-60}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Initialize state directory and file
init_state() {
    local state_dir
    state_dir="$(dirname "$STATE_FILE")"
    log "Using state file: $STATE_FILE"
    
    if [[ ! -d "$state_dir" ]]; then
        mkdir -p "$state_dir" 2>/dev/null || {
            log "WARNING: Cannot create state directory $state_dir, using /tmp"
            STATE_FILE="/tmp/wireguard-exporter-state"
            log "State file changed to: $STATE_FILE"
        }
    fi
    
    if [[ ! -f "$STATE_FILE" ]]; then
        log "Initializing new state file"
        # Initialize state file with empty values
        cat > "$STATE_FILE" <<EOF
# WireGuard Exporter State File
# This file tracks previous values for rate calculations
EOF
    fi
}

# Load state from file
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
    fi
}

# Save state to file
save_state() {
    # State is saved dynamically as needed
    :
}

# Helper function to execute wg commands (supports Docker containers)
wg_exec() {
    if [[ -n "$WIREGUARD_DOCKER_CONTAINER" ]]; then
        docker exec "$WIREGUARD_DOCKER_CONTAINER" wg "$@" 2>/dev/null
    else
        wg "$@" 2>/dev/null
    fi
}

# Helper function to execute ip commands (supports Docker containers)
ip_exec() {
    if [[ -n "$WIREGUARD_DOCKER_CONTAINER" ]]; then
        docker exec "$WIREGUARD_DOCKER_CONTAINER" ip "$@" 2>/dev/null
    else
        ip "$@" 2>/dev/null
    fi
}

# Array to track metrics that have been defined
declare -A METRIC_DEFINED

# Function to format Prometheus metric
format_metric() {
    local metric_name="$1"
    local value="$2"
    local labels="$3"
    local help="$4"
    local type="${5:-gauge}"
    
    local full_name="${METRICS_PREFIX}_${metric_name}"

    # Only output HELP and TYPE once per metric name
    if [[ -z "${METRIC_DEFINED[$full_name]:-}" ]]; then
        echo "# HELP ${full_name} ${help}"
        echo "# TYPE ${full_name} ${type}"
        METRIC_DEFINED[$full_name]=1
    fi
    
    if [[ -n "$labels" ]]; then
        echo "${full_name}{${labels}} ${value}"
    else
        echo "${full_name} ${value}"
    fi
}

# Get list of WireGuard interfaces
get_interfaces() {
    if [[ -n "$WIREGUARD_INTERFACE" ]]; then
        echo "$WIREGUARD_INTERFACE"
    else
        # Auto-detect all WireGuard interfaces
        wg_exec show interfaces | tr ' ' '\n' || echo ""
    fi
}

# Function to collect interface metrics
collect_interface_metrics() {
    local interface="$1"
    
    # Get interface info
    local listen_port
    listen_port=$(wg_exec show "$interface" listen-port || echo "0")
    
    local public_key
    public_key=$(wg_exec show "$interface" public-key || echo "")
    
    local peers_count
    peers_count=$(wg_exec show "$interface" peers | wc -l || echo "0")
    
    # Interface up status
    if ip_exec link show "$interface" &>/dev/null; then
        format_metric "interface_up" "1" "interface=\"${interface}\"" "WireGuard interface status (1=up, 0=down)"
    else
        format_metric "interface_up" "0" "interface=\"${interface}\"" "WireGuard interface status (1=up, 0=down)"
    fi
    
    # Listen port
    format_metric "interface_listen_port" "$listen_port" "interface=\"${interface}\"" "WireGuard interface listen port"
    
    # Number of peers
    format_metric "interface_peers" "$peers_count" "interface=\"${interface}\"" "Number of peers configured on interface"
}

# Function to collect peer metrics
collect_peer_metrics() {
    local interface="$1"
    
    # Get all peer public keys
    local peers
    peers=$(wg_exec show "$interface" peers || echo "")
    
    if [[ -z "$peers" ]]; then
        return 0
    fi
    
    # For each peer, collect detailed metrics
    while read -r peer_pubkey; do
        [[ -z "$peer_pubkey" ]] && continue
        
        # Get peer info using wg show dump format for better parsing
        local peer_info
        peer_info=$(wg_exec show "$interface" dump | grep "^${peer_pubkey}" || echo "")
        
        if [[ -z "$peer_info" ]]; then
            continue
        fi
        
        # Parse dump format: public-key preshared-key endpoint allowed-ips latest-handshake transfer-rx transfer-tx persistent-keepalive
        local endpoint allowed_ips latest_handshake transfer_rx transfer_tx persistent_keepalive
        
        endpoint=$(echo "$peer_info" | awk '{print $3}')
        allowed_ips=$(echo "$peer_info" | awk '{print $4}')
        latest_handshake=$(echo "$peer_info" | awk '{print $5}')
        transfer_rx=$(echo "$peer_info" | awk '{print $6}')
        transfer_tx=$(echo "$peer_info" | awk '{print $7}')
        persistent_keepalive=$(echo "$peer_info" | awk '{print $8}')
        
        # Use short version of public key for labels (first 8 chars)
        local peer_short="${peer_pubkey:0:8}"
        
        # Peer connected status (handshake within last 3 minutes = 180 seconds)
        local current_time
        current_time=$(date +%s)
        local time_since_handshake=$((current_time - latest_handshake))
        
        if [[ "$latest_handshake" != "0" ]] && [[ $time_since_handshake -lt 180 ]]; then
            format_metric "peer_connected" "1" "interface=\"${interface}\",public_key=\"${peer_short}\",endpoint=\"${endpoint}\"" "Peer connection status (1=connected, 0=disconnected)"
        else
            format_metric "peer_connected" "0" "interface=\"${interface}\",public_key=\"${peer_short}\",endpoint=\"${endpoint}\"" "Peer connection status (1=connected, 0=disconnected)"
        fi
        
        # Latest handshake timestamp
        format_metric "peer_latest_handshake_seconds" "$latest_handshake" "interface=\"${interface}\",public_key=\"${peer_short}\",endpoint=\"${endpoint}\"" "UNIX timestamp of the last handshake" "gauge"
        
        # Bytes received
        format_metric "peer_receive_bytes_total" "$transfer_rx" "interface=\"${interface}\",public_key=\"${peer_short}\",endpoint=\"${endpoint}\"" "Total bytes received from peer" "counter"
        
        # Bytes transmitted
        format_metric "peer_transmit_bytes_total" "$transfer_tx" "interface=\"${interface}\",public_key=\"${peer_short}\",endpoint=\"${endpoint}\"" "Total bytes transmitted to peer" "counter"
        
        # Persistent keepalive interval
        if [[ "$persistent_keepalive" != "off" ]] && [[ "$persistent_keepalive" != "0" ]]; then
            format_metric "peer_persistent_keepalive_interval" "$persistent_keepalive" "interface=\"${interface}\",public_key=\"${peer_short}\",endpoint=\"${endpoint}\"" "Persistent keepalive interval in seconds"
        else
            format_metric "peer_persistent_keepalive_interval" "0" "interface=\"${interface}\",public_key=\"${peer_short}\",endpoint=\"${endpoint}\"" "Persistent keepalive interval in seconds"
        fi
        
        # Number of allowed IPs
        local allowed_ips_count
        allowed_ips_count=$(echo "$allowed_ips" | tr ',' '\n' | wc -l)
        format_metric "peer_allowed_ips_count" "$allowed_ips_count" "interface=\"${interface}\",public_key=\"${peer_short}\",endpoint=\"${endpoint}\"" "Number of allowed IP ranges for peer"
        
    done <<< "$peers"
}

# Function to get WireGuard version
get_version_info() {
    local version
    
    if command -v wg >/dev/null 2>&1; then
        version=$(wg --version 2>&1 | head -1 | awk '{print $2}' || echo "unknown")
        format_metric "version_info" "1" "version=\"${version}\"" "WireGuard version information"
    fi
}

# Main function to collect and output all metrics
collect_metrics() {
    # Output metrics header
    echo "# WireGuard VPN Metrics"
    echo "# Generated at $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""
    
    # Collect version info
    get_version_info
    echo ""
    
    # Get all interfaces
    local interfaces
    interfaces=$(get_interfaces)
    
    if [[ -z "$interfaces" ]]; then
        log "WARNING: No WireGuard interfaces found"
        format_metric "interfaces_total" "0" "" "Total number of WireGuard interfaces"
        return 0
    fi
    
    # Count total interfaces
    local interface_count
    interface_count=$(echo "$interfaces" | wc -l)
    format_metric "interfaces_total" "$interface_count" "" "Total number of WireGuard interfaces"
    echo ""
    
    # Collect metrics for each interface
    while read -r interface; do
        [[ -z "$interface" ]] && continue
        
        log "Collecting metrics for interface: $interface"
        
        # Collect interface metrics
        collect_interface_metrics "$interface"
        echo ""
        
        # Collect peer metrics
        collect_peer_metrics "$interface"
        echo ""
        
    done <<< "$interfaces"
}

# Function to test connectivity
test_connection() {
    log "Testing WireGuard exporter configuration..."
    
    local errors=0
    
    # Check if Docker container is specified
    if [[ -n "$WIREGUARD_DOCKER_CONTAINER" ]]; then
        log "Docker mode enabled: monitoring container '$WIREGUARD_DOCKER_CONTAINER'"
        
        # Check if docker command is available
        if ! command -v docker >/dev/null 2>&1; then
            log "ERROR: docker command not found. Please install Docker"
            errors=$((errors + 1))
        else
            log "SUCCESS: docker command is available"
        fi
        
        # Check if container exists and is running
        if ! docker ps --format '{{.Names}}' | grep -q "^${WIREGUARD_DOCKER_CONTAINER}$"; then
            log "ERROR: Container '$WIREGUARD_DOCKER_CONTAINER' is not running"
            log "Running containers: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"
            errors=$((errors + 1))
        else
            log "SUCCESS: Container '$WIREGUARD_DOCKER_CONTAINER' is running"
        fi
        
        # Check if wg command is available in container
        if ! docker exec "$WIREGUARD_DOCKER_CONTAINER" which wg &>/dev/null; then
            log "ERROR: wg command not found in container"
            errors=$((errors + 1))
        else
            log "SUCCESS: wg command is available in container"
            
            # Check wg version in container
            local version
            version=$(docker exec "$WIREGUARD_DOCKER_CONTAINER" wg --version 2>&1 | head -1 || echo "unknown")
            log "WireGuard version (in container): $version"
        fi
    else
        log "Host mode: monitoring WireGuard on local system"
        
        # Check if wg command is available
        if ! command -v wg >/dev/null 2>&1; then
            log "ERROR: wg command not found. Please install wireguard-tools"
            errors=$((errors + 1))
        else
            log "SUCCESS: wg command is available"
            
            # Check wg version
            local version
            version=$(wg --version 2>&1 | head -1 || echo "unknown")
            log "WireGuard version: $version"
        fi
        
        # Check if we have permission to run wg
        if ! wg show &>/dev/null; then
            log "WARNING: Cannot execute 'wg show'. You may need to run as root or with CAP_NET_ADMIN"
            log "Try: sudo $0 test"
            errors=$((errors + 1))
        else
            log "SUCCESS: Can execute 'wg show'"
        fi
    fi
    
    # Check for interfaces
    local interfaces
    interfaces=$(get_interfaces)
    
    if [[ -z "$interfaces" ]]; then
        log "WARNING: No WireGuard interfaces found"
        log "Make sure WireGuard is configured and interfaces are up"
        errors=$((errors + 1))
    else
        log "SUCCESS: Found WireGuard interface(s): $(echo $interfaces | tr '\n' ' ')"
        
        # Show interface details
        while read -r interface; do
            [[ -z "$interface" ]] && continue
            
            local peers_count
            peers_count=$(wg show "$interface" peers 2>/dev/null | wc -l || echo "0")
            log "Interface $interface has $peers_count peer(s)"
        done <<< "$interfaces"
    fi
    
    # Check state directory
    local state_dir
    state_dir="$(dirname "$STATE_FILE")"
    if [[ ! -d "$state_dir" ]]; then
        log "WARNING: State directory does not exist: $state_dir"
        if mkdir -p "$state_dir" 2>/dev/null; then
            log "SUCCESS: Created state directory"
        else
            log "WARNING: Cannot create state directory, will use /tmp"
        fi
    else
        log "SUCCESS: State directory exists: $state_dir"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Configuration test completed successfully"
        return 0
    else
        log "Configuration test completed with $errors errors/warnings"
        return 1
    fi
}

# Handle command line arguments
case "${1:-collect}" in
    "collect"|"metrics"|"")
        # Initialize and load state before collecting metrics
        init_state
        load_state
        
        # Collect and output metrics
        collect_metrics
        
        # Save state after collecting metrics
        save_state
        ;;
    "test")
        test_connection
        ;;
    "version")
        echo "WireGuard Exporter v1.0.0"
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [collect|test|version|help]"
        echo ""
        echo "Commands:"
        echo "  collect  - Collect and output Prometheus metrics (default)"
        echo "  test     - Test configuration and WireGuard accessibility"
        echo "  version  - Show exporter version"
        echo "  help     - Show this help message"
        echo ""
        echo "Environment variables:"
        echo "  WIREGUARD_INTERFACE        - Specific interface to monitor (default: all interfaces)"
        echo "  WIREGUARD_DOCKER_CONTAINER - Docker container name running WireGuard (optional)"
        echo "  METRICS_PREFIX             - Metrics prefix (default: wireguard)"
        echo "  STATE_FILE                 - State file for persistent data (default: /var/lib/wireguard-exporter/state)"
        ;;
    *)
        log "ERROR: Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
