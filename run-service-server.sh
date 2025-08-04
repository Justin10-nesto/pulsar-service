#!/bin/bash

set -e  # Exit on any error

echo "=== Apache Pulsar Service Startup Script (Server Version) ==="
echo "Current directory: $(pwd)"
echo "Date: $(date)"
echo "User: $(whoami)"
echo "UID: $(id -u), GID: $(id -g)"
echo ""

# Function to create directory if it doesn't exist
create_directory() {
    local dir_path="$1"
    
    echo "Setting up directory: $dir_path"
    
    # Remove existing directory if it has permission issues
    if [ -d "$dir_path" ] && [ ! -w "$dir_path" ]; then
        echo "Directory exists but is not writable, attempting to fix permissions..."
        sudo rm -rf "$dir_path" 2>/dev/null || rm -rf "$dir_path" 2>/dev/null || true
    fi
    
    # Create directory structure
    mkdir -p "$dir_path"
    
    # Create specific subdirectories
    if [[ "$dir_path" == *"zookeeper"* ]]; then
        mkdir -p "$dir_path/version-2"
        echo "✓ Created ZooKeeper version-2 subdirectory"
    fi
    
    # Set permissions - try different approaches
    chmod -R 755 "$dir_path" 2>/dev/null || true
    
    # Set ownership - try multiple user/group combinations
    if command -v chown >/dev/null 2>&1; then
        # Try common Pulsar container user IDs
        chown -R 10000:10000 "$dir_path" 2>/dev/null || \
        chown -R 1000:1000 "$dir_path" 2>/dev/null || \
        chown -R $(id -u):$(id -g) "$dir_path" 2>/dev/null || \
        sudo chown -R 10000:10000 "$dir_path" 2>/dev/null || \
        sudo chown -R 1000:1000 "$dir_path" 2>/dev/null || {
            echo "Warning: Could not set ownership for $dir_path"
        }
    fi
    
    # Make directories world-writable as fallback
    chmod -R 777 "$dir_path" 2>/dev/null || true
    
    echo "✓ Directory setup completed: $dir_path"
    ls -la "$dir_path" 2>/dev/null || true
}

echo "1. Creating required data directories with proper permissions..."

# Create data directories
create_directory "data/zookeeper"
create_directory "data/bookkeeper"
create_directory "logs"

echo ""
echo "2. Checking Docker and Docker Compose..."

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Error: Docker is not running or not installed."
    echo "Please make sure Docker is running and try again."
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

echo ""
echo "3. Cleaning up any existing containers..."
$DOCKER_COMPOSE_CMD down --remove-orphans 2>/dev/null || true

echo ""
echo "4. Pulling latest images..."
$DOCKER_COMPOSE_CMD pull

echo ""
echo "5. Starting Apache Pulsar services..."
echo "This may take a few minutes for the first startup..."

# Start services with proper logging
$DOCKER_COMPOSE_CMD up -d

echo ""
echo "6. Waiting for services to be healthy..."

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
            echo "Checking $service_name logs:"
            docker logs "$service_name" --tail 20
            return 1
        fi
        
        echo -n "."
        sleep 5
        ((attempt++))
    done
    
    echo " ⏰ (timeout)"
    echo "Checking $service_name logs:"
    docker logs "$service_name" --tail 20
    return 1
}

# Check ZooKeeper health first
if check_service_health "zookeeper"; then
    echo "ZooKeeper is healthy"
else
    echo "❌ ZooKeeper failed to start properly"
    echo ""
    echo "Troubleshooting information:"
    echo "Host data directory permissions:"
    ls -la data/zookeeper/ 2>/dev/null || echo "Cannot access data/zookeeper/"
    echo ""
    echo "Container data directory permissions:"
    docker exec zookeeper ls -la /pulsar/data/zookeeper/ 2>/dev/null || echo "Cannot access container directory"
    echo ""
    echo "ZooKeeper container logs:"
    docker logs zookeeper --tail 50
    exit 1
fi

# Wait a bit more for other services
sleep 10

echo ""
echo "7. Service Status:"
echo "===================="
$DOCKER_COMPOSE_CMD ps

echo ""
echo "8. Service URLs:"
echo "===================="
echo "Pulsar Broker:          http://localhost:8080"
echo "Pulsar Admin REST API:  http://localhost:8080/admin/v2"
echo "Pulsar Manager:         http://localhost:9527"
echo "Pulsar Service URL:     pulsar://localhost:6650"
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
