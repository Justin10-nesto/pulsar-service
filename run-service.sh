#!/bin/bash

set -e  # Exit on any error

echo "=== Apache Pulsar Service Startup Script ==="
echo "Current directory: $(pwd)"
echo "Date: $(date)"
echo ""

# Function to get host IP address (private/internal)
get_host_ip() {
    local ip=""
    
    # Try to get hostname IP first (works on most systems)
    if command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    # If hostname failed, try ip command (Linux)
    if [[ -z "$ip" ]] && command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -n1)
    fi
    
    # If still no IP, try ifconfig (macOS/Linux)
    if [[ -z "$ip" ]] && command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig | grep -E "inet ([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{print $2}' | head -n1)
    fi
    
    # If still no IP, try ipconfig (Windows)
    if [[ -z "$ip" ]] && command -v ipconfig >/dev/null 2>&1; then
        ip=$(ipconfig | grep -E "IPv4.*: ([0-9]{1,3}\.){3}[0-9]{1,3}" | head -n1 | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
    fi
    
    # Fallback to localhost if no IP found
    if [[ -z "$ip" ]]; then
        ip="localhost"
        echo "Warning: Could not detect IP address, using localhost"
    fi
    
    echo "$ip"
}

# Function to get public IP address
get_public_ip() {
    local public_ip=""
    
    echo "Detecting public IP address..."
    # Try multiple public IP services with longer timeout
    public_ip=$(curl -s --connect-timeout 10 --max-time 15 ifconfig.me 2>/dev/null) || 
    public_ip=$(curl -s --connect-timeout 10 --max-time 15 ipinfo.io/ip 2>/dev/null) || 
    public_ip=$(curl -s --connect-timeout 10 --max-time 15 api.ipify.org 2>/dev/null) ||
    public_ip=$(curl -s --connect-timeout 10 --max-time 15 icanhazip.com 2>/dev/null)
    
    # Remove any whitespace
    public_ip=$(echo "$public_ip" | tr -d '[:space:]')
    
    echo "$public_ip"
}

# Function to create directory if it doesn't exist with proper permissions
create_directory() {
    local dir_path="$1"
    
    if [ ! -d "$dir_path" ]; then
        echo "Creating directory: $dir_path"
        mkdir -p "$dir_path"
        echo "✓ Directory created: $dir_path"
    else
        echo "✓ Directory already exists: $dir_path"
    fi
    
    # Create specific subdirectories for ZooKeeper and BookKeeper
    if [[ "$dir_path" == *"zookeeper"* ]]; then
        mkdir -p "$dir_path/version-2"
        echo "✓ Created ZooKeeper version-2 subdirectory"
    fi
    
    # Set comprehensive permissions for all users (777) to avoid permission issues
    if command -v chmod >/dev/null 2>&1; then
        chmod -R 777 "$dir_path" 2>/dev/null || {
            echo "Warning: Could not set permissions for $dir_path"
        }
        echo "✓ Set permissions (777) for $dir_path"
    fi
    
    # Try to set ownership with various common user IDs
    if command -v chown >/dev/null 2>&1; then
        # Try different user IDs that Pulsar containers might use
        chown -R 10000:10000 "$dir_path" 2>/dev/null || \
        chown -R 1000:1000 "$dir_path" 2>/dev/null || \
        chown -R 999:999 "$dir_path" 2>/dev/null || \
        chown -R $(id -u):$(id -g) "$dir_path" 2>/dev/null || {
            echo "Warning: Could not set ownership for $dir_path (this might be normal on Windows)"
        }
    fi
}

echo "1. Creating required data directories with proper permissions..."

# Create directories with comprehensive permissions
create_directory "data"
create_directory "data/zookeeper"
create_directory "data/bookkeeper"
create_directory "logs"

echo ""
echo "2. Detecting and configuring IP addresses..."

# Get both private and public IPs
PRIVATE_IP=$(get_host_ip)
echo "Detected Private IP: $PRIVATE_IP"

PUBLIC_IP=$(get_public_ip)
if [ -n "$PUBLIC_IP" ] && [[ "$PUBLIC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "Detected Public IP: $PUBLIC_IP"
else
    echo "Could not detect Public IP (using private IP as fallback)"
    PUBLIC_IP=""
fi

# Check existing .env file for manual configuration
EXISTING_BROKER_IP=""
EXISTING_USE_PUBLIC_IP=""
if [ -f ".env" ]; then
    EXISTING_BROKER_IP=$(grep "^PULSAR_BROKER_IP=" .env 2>/dev/null | cut -d'=' -f2)
    EXISTING_USE_PUBLIC_IP=$(grep "^USE_PUBLIC_IP=" .env 2>/dev/null | cut -d'=' -f2)
    if [ -n "$EXISTING_BROKER_IP" ]; then
        echo "Found existing PULSAR_BROKER_IP in .env: $EXISTING_BROKER_IP"
    fi
    if [ -n "$EXISTING_USE_PUBLIC_IP" ]; then
        echo "Found existing USE_PUBLIC_IP in .env: $EXISTING_USE_PUBLIC_IP"
    fi
fi

# Determine selected IP with precedence:
# 1) If USE_PUBLIC_IP=false explicitly in .env, respect it and use existing broker IP (or private IP)
# 2) If public IP detected, prefer public IP
# 3) Else use existing broker IP if set
# 4) Else fall back to private IP

if [ -n "$EXISTING_USE_PUBLIC_IP" ] && [[ "$EXISTING_USE_PUBLIC_IP" =~ ^([Tt]rue|1)$ ]]; then
    if [ -n "$PUBLIC_IP" ]; then
        SELECTED_IP="$PUBLIC_IP"
        USE_PUBLIC_IP="true"
        echo "✓ USE_PUBLIC_IP=true in .env — using public IP: $SELECTED_IP"
    elif [ -n "$EXISTING_BROKER_IP" ]; then
        SELECTED_IP="$EXISTING_BROKER_IP"
        USE_PUBLIC_IP="true"
        echo "✓ USE_PUBLIC_IP=true in .env but public IP not detected — keeping PULSAR_BROKER_IP from .env: $SELECTED_IP"
    fi
elif [ -n "$EXISTING_USE_PUBLIC_IP" ] && [[ "$EXISTING_USE_PUBLIC_IP" =~ ^([Ff]alse|0)$ ]]; then
    # Respect explicit false: use existing broker IP if present, else private
    if [ -n "$EXISTING_BROKER_IP" ]; then
        SELECTED_IP="$EXISTING_BROKER_IP"
        USE_PUBLIC_IP="false"
        echo "✓ USE_PUBLIC_IP=false in .env — using PULSAR_BROKER_IP from .env: $SELECTED_IP"
    else
        SELECTED_IP="$PRIVATE_IP"
        USE_PUBLIC_IP="false"
        echo "✓ USE_PUBLIC_IP=false in .env but no PULSAR_BROKER_IP — using private IP: $SELECTED_IP"
    fi
else
    # No explicit USE_PUBLIC_IP in .env; prefer detected public IP when available
    if [ -n "$PUBLIC_IP" ]; then
        # If existing broker IP is set and differs, ask user whether to keep manual override
        if [ -n "$EXISTING_BROKER_IP" ] && [ "$EXISTING_BROKER_IP" != "$PUBLIC_IP" ]; then
            echo "Found manual PULSAR_BROKER_IP in .env: $EXISTING_BROKER_IP"
            echo "Detected public IP: $PUBLIC_IP"
            echo "Do you want to keep the manual IP ($EXISTING_BROKER_IP) or use the detected public IP ($PUBLIC_IP)?"
            read -p "Keep manual? [y/N]: " keep_manual
            keep_manual=${keep_manual:-N}
            if [[ "$keep_manual" =~ ^[Yy]$ ]]; then
                SELECTED_IP="$EXISTING_BROKER_IP"
                USE_PUBLIC_IP="${EXISTING_USE_PUBLIC_IP:-false}"
                echo "✓ Keeping manual IP: $SELECTED_IP"
            else
                SELECTED_IP="$PUBLIC_IP"
                USE_PUBLIC_IP="true"
                echo "✓ Using detected public IP: $SELECTED_IP"
            fi
        else
            SELECTED_IP="$PUBLIC_IP"
            USE_PUBLIC_IP="true"
            echo "✓ Using detected public IP: $SELECTED_IP"
        fi
    else
        # No public IP; prefer existing broker IP if set, otherwise private IP
        if [ -n "$EXISTING_BROKER_IP" ]; then
            SELECTED_IP="$EXISTING_BROKER_IP"
            USE_PUBLIC_IP="${EXISTING_USE_PUBLIC_IP:-false}"
            echo "✓ No public IP detected — using existing PULSAR_BROKER_IP: $SELECTED_IP"
        else
            SELECTED_IP="$PRIVATE_IP"
            USE_PUBLIC_IP="false"
            echo "✓ No public IP or manual IP — using private IP: $SELECTED_IP"
        fi
    fi
fi

echo ""
echo "💡 IP Configuration Summary:"
echo "   - Selected IP: $SELECTED_IP"
echo "   - Private IP: $PRIVATE_IP"
if [ -n "$PUBLIC_IP" ]; then
    echo "   - Public IP: $PUBLIC_IP"
    echo "   - Public IP access requires firewall configuration for ports: 6650, 8080, 9527"
fi
echo "   - Use Public IP: $USE_PUBLIC_IP"

# Create or update .env file with proper permissions
echo "PULSAR_BROKER_IP=$SELECTED_IP" > .env
echo "PULSAR_CLUSTER_NAME=cluster-a" >> .env
echo "USE_PUBLIC_IP=$USE_PUBLIC_IP" >> .env
echo "PULSAR_MANAGER_PASSWORD=admin123" >> .env
echo "# Pulsar Configuration" >> .env
echo "# PULSAR_BROKER_IP: IP address that clients will use to connect" >> .env
echo "# USE_PUBLIC_IP: Set to 'true' for external access, 'false' for local" >> .env
echo "# Public IP requires firewall configuration for ports 6650, 8080, 9527" >> .env

# Set proper permissions for .env file
chmod 644 .env 2>/dev/null || true

echo "✓ Updated .env file with PULSAR_BROKER_IP=$SELECTED_IP"

echo ""
echo "3. Checking Docker and Docker Compose..."

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Error: Docker is not running or not installed."
    echo "Please make sure Docker Desktop is running and try again."
    exit 1
fi
echo "✓ Docker is running"

# Check if Docker Compose is available
if ! docker compose version >/dev/null 2>&1; then
    if ! docker-compose --version >/dev/null 2>&1; then
        echo "❌ Error: Docker Compose is not available."
        exit 1
    else
        DOCKER_COMPOSE_CMD="docker-compose"
    fi
else
    DOCKER_COMPOSE_CMD="docker compose"
fi

echo "✓ Docker Compose is available"

# Export environment variables for docker compose
set -a  # automatically export all variables
source .env
set +a  # stop automatically exporting

echo ""
echo "4. Cleaning up any existing containers..."
$DOCKER_COMPOSE_CMD down --remove-orphans --volumes 2>/dev/null || true

echo ""
echo "5. Pulling latest images..."
$DOCKER_COMPOSE_CMD pull

echo ""
echo "6. Starting Apache Pulsar services..."
echo "This may take a few minutes for the first startup..."

# Start services with proper logging
$DOCKER_COMPOSE_CMD up -d

echo ""
echo "7. Waiting for services to be healthy..."

# Function to check service health
check_service_health() {
    local service_name="$1"
    local max_attempts=60  # 5 minutes max wait time
    local attempt=1
    
    echo -n "Checking $service_name health"
    
    while [ $attempt -le $max_attempts ]; do
        if docker ps --filter "name=$service_name" --filter "health=healthy" --format "{{.Names}}" | grep -q "$service_name"; then
            echo " ✓"
            return 0
        elif docker ps --filter "name=$service_name" --filter "health=unhealthy" --format "{{.Names}}" | grep -q "$service_name"; then
            echo " ❌ (unhealthy)"
            return 1
        fi
        
        echo -n "."
        sleep 5
        ((attempt++))
    done
    
    echo " ⏰ (timeout)"
    return 1
}

# Check ZooKeeper health first
if check_service_health "zookeeper"; then
    echo "ZooKeeper is healthy"
else
    echo "❌ ZooKeeper failed to start properly"
    echo "Checking ZooKeeper logs:"
    docker logs zookeeper --tail 20
    exit 1
fi

# Wait a bit more for other services
sleep 10

echo ""
echo "8. Service Status:"
echo "===================="
$DOCKER_COMPOSE_CMD ps

echo ""
echo "9. Service URLs:"
echo "===================="
echo "Pulsar Broker:          http://$SELECTED_IP:8080"
echo "Pulsar Admin REST API:  http://$SELECTED_IP:8080/admin/v2"
echo "Pulsar Manager:         http://$SELECTED_IP:9527"
echo "Pulsar Service URL:     pulsar://$SELECTED_IP:6650"
echo ""
echo "Default Pulsar Manager credentials:"
echo "Username: admin"
echo "Password: admin123"

echo ""
echo "🎉 Apache Pulsar services started successfully!"
echo ""
echo "Configuration Details:"
echo "======================"
echo "Selected IP: $SELECTED_IP"
echo "IP Type: $([ "$USE_PUBLIC_IP" = "true" ] && echo "Public" || echo "Private")"
echo "Data Directory Permissions: 777 (full access)"
echo ""
echo "Management Commands:"
echo "==================="
echo "Stop services:     $DOCKER_COMPOSE_CMD down"
echo "View logs:         docker logs <service-name> -f"
echo "Check status:      $DOCKER_COMPOSE_CMD ps"
echo "Restart services:  bash run-service.sh"
echo ""
echo "To manually configure IP, edit .env file and set:"
echo "PULSAR_BROKER_IP=<your-desired-ip>"
echo "USE_PUBLIC_IP=true|false"