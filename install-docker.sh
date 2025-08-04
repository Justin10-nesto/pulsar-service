#!/bin/bash

set -e  # Exit on any error

echo "=== Docker Installation Script for Windows ==="
echo "This script will help you install Docker Desktop on Windows"
echo ""

# Check if running on Windows
if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" && "$OSTYPE" != "win32" ]]; then
    echo "❌ This script is designed for Windows. For other operating systems, please refer to Docker's official documentation."
    exit 1
fi

# Check if Docker is already installed
if command -v docker >/dev/null 2>&1; then
    echo "✓ Docker is already installed:"
    docker --version
    
    if docker info >/dev/null 2>&1; then
        echo "✓ Docker is running"
    else
        echo "⚠️  Docker is installed but not running. Please start Docker Desktop."
    fi
    
    echo ""
    echo "To run the Pulsar service, execute:"
    echo "  ./run-service.sh"
    exit 0
fi

echo "Docker is not installed. Please follow these steps to install Docker Desktop:"
echo ""
echo "1. Download Docker Desktop for Windows:"
echo "   https://desktop.docker.com/win/stable/Docker%20Desktop%20Installer.exe"
echo ""
echo "2. Run the installer and follow the installation wizard"
echo ""
echo "3. After installation, restart your computer if prompted"
echo ""
echo "4. Start Docker Desktop from the Start menu"
echo ""
echo "5. Wait for Docker to start (you'll see the Docker whale icon in the system tray)"
echo ""
echo "6. Open a new terminal and run this script again to verify the installation"
echo ""
echo "System Requirements:"
echo "- Windows 10 64-bit: Pro, Enterprise, or Education (Build 15063 or later)"
echo "- Windows 11 64-bit: Home or Pro version 21H2 or higher"
echo "- WSL 2 feature enabled"
echo "- Virtualization enabled in BIOS"
echo ""
echo "For manual installation steps, visit:"
echo "https://docs.docker.com/desktop/install/windows-install/"
