#!/bin/bash

set -e

echo "=== Apache Pulsar Production Deployment ==="
echo "Date: $(date)"
echo ""

# Production checks
echo "1. Running production readiness checks..."

# Check system requirements
check_system_requirements() {
    echo "Checking system requirements..."
    
    # Check available memory (at least 4GB recommended)
    if command -v free >/dev/null 2>&1; then
        total_mem=$(free -g | awk '/^Mem:/{print $2}')
        if [ "$total_mem" -lt 4 ]; then
            echo "⚠️  Warning: Less than 4GB RAM available. Consider upgrading for production use."
        else
            echo "✓ Memory: ${total_mem}GB available"
        fi
    fi
    
    # Check disk space (at least 20GB recommended)
    available_space=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 20 ]; then
        echo "⚠️  Warning: Less than 20GB disk space available. Consider adding more storage."
    else
        echo "✓ Disk space: ${available_space}GB available"
    fi
    
    # Check Docker version
    docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo "✓ Docker version: $docker_version"
    
    # Check if running as root in production
    if [ "$EUID" -eq 0 ]; then
        echo "⚠️  Warning: Running as root. Consider using a dedicated user for production."
    fi
}

check_system_requirements

echo ""
echo "2. Loading production configuration..."

# Load production environment
if [ -f ".env.production" ]; then
    echo "✓ Loading .env.production"
    cp .env.production .env
else
    echo "❌ .env.production file not found! Please create one first."
    exit 1
fi

# Function to get host IP address (production version)
get_host_ip() {
    local ip=""
    
    # In production, prefer explicitly set IP
    if [ -n "$PULSAR_EXTERNAL_IP" ]; then
        ip="$PULSAR_EXTERNAL_IP"
        echo "Using explicitly set IP: $ip"
        return
    fi
    
    # Try different methods to get IP address
    if command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}' | head -n1)
    fi
    
    if [[ -z "$ip" ]] && command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -n1)
    fi
    
    if [[ -z "$ip" ]] && command -v curl >/dev/null 2>&1; then
        # Try to get public IP for cloud deployments
        ip=$(curl -s http://checkip.amazonaws.com/ 2>/dev/null || curl -s http://ipecho.net/plain 2>/dev/null || echo "")
    fi
    
    if [[ -z "$ip" ]]; then
        echo "❌ Could not detect IP address. Please set PULSAR_EXTERNAL_IP environment variable."
        exit 1
    fi
    
    echo "$ip"
}

# Update IP in environment
HOST_IP=$(get_host_ip)
echo "✓ Detected/Using IP address: $HOST_IP"

# Update .env with detected IP
sed -i.bak "s/PULSAR_BROKER_IP=.*/PULSAR_BROKER_IP=$HOST_IP/" .env
echo "✓ Updated .env with production IP"

echo ""
echo "3. Setting up production data directories..."

# Create production data directories with proper permissions
create_production_directory() {
    local dir_path="$1"
    local mode="${2:-755}"
    
    if [ ! -d "$dir_path" ]; then
        mkdir -p "$dir_path"
        echo "✓ Created: $dir_path"
    fi
    
    # Set production permissions
    chmod "$mode" "$dir_path"
    
    # Set ownership if not root
    if [ "$EUID" -ne 0 ] && command -v chown >/dev/null 2>&1; then
        chown -R $(id -u):$(id -g) "$dir_path" 2>/dev/null || true
    fi
}

create_production_directory "data" 755
create_production_directory "data/zookeeper" 755
create_production_directory "data/bookkeeper" 755
create_production_directory "data/pulsar" 755
create_production_directory "logs" 755
create_production_directory "backup" 755

echo ""
echo "4. Validating Docker Compose configuration..."

# Validate docker-compose configuration
if ! docker compose config >/dev/null 2>&1; then
    echo "❌ Docker Compose configuration is invalid!"
    exit 1
fi
echo "✓ Docker Compose configuration is valid"

echo ""
echo "5. Stopping existing services (if any)..."
docker compose down --remove-orphans 2>/dev/null || true

echo ""
echo "6. Pulling latest production images..."
docker compose pull

echo ""
echo "7. Starting production services..."
docker compose up -d

echo ""
echo "8. Waiting for services to be healthy..."

# Enhanced health check for production
wait_for_service() {
    local service_name="$1"
    local max_attempts=60
    local attempt=1
    
    echo -n "Waiting for $service_name to be healthy"
    
    while [ $attempt -le $max_attempts ]; do
        if docker ps --filter "name=$service_name" --filter "health=healthy" --format "{{.Names}}" | grep -q "$service_name"; then
            echo " ✓"
            return 0
        elif docker ps --filter "name=$service_name" --filter "health=unhealthy" --format "{{.Names}}" | grep -q "$service_name"; then
            echo " ❌"
            echo "Service $service_name is unhealthy. Checking logs:"
            docker logs "$service_name" --tail 20
            return 1
        fi
        
        echo -n "."
        sleep 5
        ((attempt++))
    done
    
    echo " ⏰ (timeout)"
    echo "Service $service_name failed to become healthy within expected time."
    docker logs "$service_name" --tail 20
    return 1
}

# Wait for services in order
wait_for_service "zookeeper"
wait_for_service "bookie"
wait_for_service "broker"
wait_for_service "pulsar-manager"

echo ""
echo "9. Running production validation tests..."

# Test broker connectivity
echo -n "Testing broker connectivity"
for i in {1..5}; do
    if curl -s "http://$HOST_IP:8080/admin/v2/namespaces/public" >/dev/null 2>&1; then
        echo " ✓"
        break
    fi
    echo -n "."
    sleep 2
done

# Test topic creation
echo -n "Testing topic operations"
if docker exec broker bin/pulsar-admin topics create persistent://public/default/test-topic >/dev/null 2>&1; then
    docker exec broker bin/pulsar-admin topics delete persistent://public/default/test-topic >/dev/null 2>&1
    echo " ✓"
else
    echo " ❌"
fi

echo ""
echo "10. Production deployment summary:"
echo "=================================="
docker compose ps

echo ""
echo "🎉 Production deployment completed successfully!"
echo ""
echo "Production Service URLs:"
echo "========================"
echo "Pulsar Broker:          http://$HOST_IP:8080"
echo "Pulsar Admin REST API:  http://$HOST_IP:8080/admin/v2"
echo "Pulsar Manager:         http://$HOST_IP:9527"
echo "Pulsar Service URL:     pulsar://$HOST_IP:6650"
echo ""
echo "Default Pulsar Manager credentials:"
echo "Username: admin"
echo "Password: $(grep PULSAR_MANAGER_PASSWORD .env | cut -d= -f2)"
echo ""
echo "Production Management Commands:"
echo "==============================="
echo "View logs:              docker logs <service-name> -f"
echo "Monitor resources:      docker stats"
echo "Backup data:            ./backup-pulsar.sh"
echo "Scale services:         docker compose up -d --scale bookie=3"
echo "Update services:        docker compose pull && docker compose up -d"
echo "Stop services:          docker compose down"
echo ""
echo "⚠️  IMPORTANT PRODUCTION NOTES:"
echo "- Monitor disk space and memory usage regularly"
echo "- Set up log rotation for container logs"
echo "- Configure firewall rules for ports 6650, 8080, 9527"
echo "- Enable authentication and authorization for production"
echo "- Set up monitoring and alerting"
echo "- Schedule regular backups"
echo "- Consider using external load balancer for high availability"
