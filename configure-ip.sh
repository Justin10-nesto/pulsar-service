#!/bin/bash

# IP Configuration Script for Apache Pulsar
# This script helps you choose between private and public IP configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Apache Pulsar IP Configuration ==="
echo "Date: $(date)"
echo ""

# Function to get host IP address (private)
get_private_ip() {
    local ip=""
    
    # Try hostname command first
    if command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    # Try ip command (Linux)
    if [[ -z "$ip" ]] && command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -n1)
    fi
    
    # Try ifconfig (macOS/Linux)
    if [[ -z "$ip" ]] && command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig | grep -E "inet ([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{print $2}' | head -n1)
    fi
    
    # Try ipconfig (Windows)
    if [[ -z "$ip" ]] && command -v ipconfig >/dev/null 2>&1; then
        ip=$(ipconfig | grep -E "IPv4.*: ([0-9]{1,3}\.){3}[0-9]{1,3}" | head -n1 | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
    fi
    
    # Fallback
    if [[ -z "$ip" ]]; then
        ip="localhost"
    fi
    
    echo "$ip"
}

# Function to get public IP address
get_public_ip() {
    local public_ip=""
    
    echo "Detecting public IP..." >&2
    public_ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null) || \
    public_ip=$(curl -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null) || \
    public_ip=$(curl -s --connect-timeout 5 api.ipify.org 2>/dev/null)
    
    echo "$public_ip"
}

# Get current IPs
echo "🔍 Detecting IP addresses..."
PRIVATE_IP=$(get_private_ip)
PUBLIC_IP=$(get_public_ip)

echo ""
echo "📍 Detected IP Addresses:"
echo "   Private IP: $PRIVATE_IP"
if [ -n "$PUBLIC_IP" ]; then
    echo "   Public IP:  $PUBLIC_IP"
else
    echo "   Public IP:  ❌ Not detected (check internet connection)"
fi

# Check current configuration
CURRENT_IP=""
CURRENT_USE_PUBLIC=""
if [ -f ".env" ]; then
    CURRENT_IP=$(grep "^PULSAR_BROKER_IP=" .env 2>/dev/null | cut -d'=' -f2)
    CURRENT_USE_PUBLIC=$(grep "^USE_PUBLIC_IP=" .env 2>/dev/null | cut -d'=' -f2)
fi

echo ""
echo "⚙️  Current Configuration:"
if [ -n "$CURRENT_IP" ]; then
    echo "   Current IP: $CURRENT_IP"
    echo "   Public Mode: ${CURRENT_USE_PUBLIC:-false}"
else
    echo "   No configuration found (.env file missing)"
fi

echo ""
echo "📖 Configuration Options:"
echo ""
echo "1) 🏠 Private IP (Local/Internal Access Only)"
echo "   - Use IP: $PRIVATE_IP"
echo "   - Access from: Same network/machine only"
echo "   - Security: Higher (internal network only)"
echo "   - Use case: Development, internal services"
echo ""

if [ -n "$PUBLIC_IP" ]; then
    echo "2) 🌐 Public IP (External Access)"
    echo "   - Use IP: $PUBLIC_IP"
    echo "   - Access from: Internet (with proper firewall setup)"
    echo "   - Security: Requires firewall configuration"
    echo "   - Use case: Production, external clients"
    echo "   - Required ports: 6650, 8080, 9527"
    echo ""
fi

echo "3) 📝 Manual IP Configuration"
echo "   - Specify custom IP address"
echo ""

echo "4) ❌ Exit without changes"

echo ""
read -p "Choose an option (1-4): " choice

case $choice in
    1)
        SELECTED_IP="$PRIVATE_IP"
        USE_PUBLIC_IP="false"
        echo ""
        echo "✅ Configuring Private IP: $SELECTED_IP"
        ;;
    2)
        if [ -n "$PUBLIC_IP" ]; then
            SELECTED_IP="$PUBLIC_IP"
            USE_PUBLIC_IP="true"
            echo ""
            echo "✅ Configuring Public IP: $SELECTED_IP"
            echo ""
            echo "⚠️  SECURITY WARNING:"
            echo "   You are enabling public access. Make sure to:"
            echo "   1. Configure firewall to allow ports 6650, 8080, 9527"
            echo "   2. Enable authentication in production"
            echo "   3. Use TLS encryption for production"
            echo "   4. Restrict access to trusted IPs when possible"
        else
            echo "❌ Public IP not available. Choose another option."
            exit 1
        fi
        ;;
    3)
        echo ""
        read -p "Enter custom IP address: " CUSTOM_IP
        if [[ $CUSTOM_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            SELECTED_IP="$CUSTOM_IP"
            if [[ $CUSTOM_IP == $PUBLIC_IP ]]; then
                USE_PUBLIC_IP="true"
            else
                USE_PUBLIC_IP="false"
            fi
            echo "✅ Configuring custom IP: $SELECTED_IP"
        else
            echo "❌ Invalid IP address format"
            exit 1
        fi
        ;;
    4)
        echo "Exiting without changes"
        exit 0
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

# Update .env file
echo ""
echo "📝 Updating configuration..."

# Create .env file
cat > .env << EOF
PULSAR_BROKER_IP=$SELECTED_IP
PULSAR_CLUSTER_NAME=cluster-a
USE_PUBLIC_IP=$USE_PUBLIC_IP

# Pulsar Manager (optional)
PULSAR_MANAGER_PASSWORD=admin123

# IP Configuration Notes:
# - USE_PUBLIC_IP=true enables external access (requires firewall config)
# - USE_PUBLIC_IP=false restricts to local/internal network access
# - Required ports for external access: 6650, 8080, 9527
EOF

echo "✅ Configuration updated:"
echo "   IP Address: $SELECTED_IP"
echo "   Public Mode: $USE_PUBLIC_IP"
echo "   Config file: .env"

echo ""
echo "🚀 Next steps:"
echo "1. Run './run-service.sh' to start Pulsar with new configuration"
echo "2. Run './monitor-pulsar.sh' to verify connectivity"
if [ "$USE_PUBLIC_IP" = "true" ]; then
    echo "3. Configure firewall to allow ports 6650, 8080, 9527"
    echo "4. Test external access from another machine"
fi

echo ""
echo "📋 Service URLs (after starting):"
echo "   Broker Admin:    http://$SELECTED_IP:8080"
echo "   Pulsar Service:  pulsar://$SELECTED_IP:6650"
echo "   Pulsar Manager:  http://$SELECTED_IP:9527"
