#!/bin/bash

set -e  # Exit on any error

echo "=== Apache Pulsar Service Startup Script ==="
echo "Current directory: $(pwd)"
echo "Date: $(date)"
echo ""

# Function to get host IP address
get_host_ip() {
    local ip=""
    
    # Try different methods to get IP address
    if command -v hostname >/dev/null 2>&1; then
        # Try hostname command first
        ip=$(hostname -I 2>/dev/null | awk '{print $1}' | head -n1)
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

# Function to create directory if it doesn't exist
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
    
    # Set proper permissions (this will work on Linux/macOS, harmless on Windows)
    if command -v chmod >/dev/null 2>&1; then
        chmod -R 755 "$dir_path" 2>/dev/null || {
            echo "Warning: Could not set permissions for $dir_path (this might be normal on Windows)"
        }
    fi
    
    # Try to set ownership (this will work on Linux, might fail on Windows/macOS)
    if command -v chown >/dev/null 2>&1; then
        # Try different user IDs that Pulsar containers might use
        chown -R 10000:10000 "$dir_path" 2>/dev/null || \
        chown -R 1000:1000 "$dir_path" 2>/dev/null || \
        chown -R $(id -u):$(id -g) "$dir_path" 2>/dev/null || {
            echo "Warning: Could not set ownership for $dir_path (this might be normal on Windows)"
        }
    fi
}

echo "1. Creating required data directories..."

# Create ZooKeeper data directory
create_directory "data/zookeeper"

# Create BookKeeper data directory
create_directory "data/bookkeeper"

# Create logs directory (optional, for better organization)
create_directory "logs"

echo ""
echo "2. Detecting and configuring IP address..."

# Get host IP and update .env file
HOST_IP=$(get_host_ip)
echo "Detected IP address: $HOST_IP"

# Create or update .env file
echo "PULSAR_BROKER_IP=$HOST_IP" > .env
echo "PULSAR_CLUSTER_NAME=cluster-a" >> .env
echo "✓ Updated .env file with PULSAR_BROKER_IP=$HOST_IP"

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

# Export env file for docker compose
export $(grep -v '^#' .env | xargs)

echo ""
echo "4. Cleaning up any existing containers..."
$DOCKER_COMPOSE_CMD down --remove-orphans 2>/dev/null || true

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
echo "Pulsar Broker:          http://$HOST_IP:8080"
echo "Pulsar Admin REST API:  http://$HOST_IP:8080/admin/v2"
echo "Pulsar Manager:         http://$HOST_IP:9527"
echo "Pulsar Service URL:     pulsar://$HOST_IP:6650"
echo ""
echo "Default Pulsar Manager credentials:"
echo "Username: pulsar"
echo "Password: pulsar"

echo ""
echo "🎉 Apache Pulsar services started successfully!"
echo ""
echo "To stop the services, run:"
echo "  $DOCKER_COMPOSE_CMD down"
echo ""
echo "To view logs for a specific service, run:"
echo "  docker logs <service-name> -f"
echo "  Example: docker logs broker -f"
echo ""
echo "To check service status:"
echo "  $DOCKER_COMPOSE_CMD ps"
