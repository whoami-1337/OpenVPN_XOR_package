#!/bin/bash

# Automatic OpenVPN XOR Package Installation Script
# This script clones the OpenVPN_XOR_package repository and installs the deb package
# Author: Automated Installation Script
# Version: 1.0

set -e  # Exit on any error

# Configuration
REPO_URL="https://github.com/whoami-1337/OpenVPN_XOR_package.git"
REPO_NAME="OpenVPN_XOR_package"
INSTALL_DIR="/tmp/openvpn_xor_install"
LOGFILE="/tmp/openvpn_xor_install.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOGFILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOGFILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOGFILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOGFILE"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root. This is recommended for package installation."
    else
        log_warning "Not running as root. Some operations may require sudo privileges."
    fi
}

# Function to check system compatibility
check_system() {
    log "Checking system compatibility..."
    
    # Check if it's a Debian-based system
    if ! command -v dpkg &> /dev/null; then
        log_error "This script requires a Debian-based system with dpkg support."
        exit 1
    fi
    
    # Check if apt is available
    if ! command -v apt &> /dev/null && ! command -v apt-get &> /dev/null; then
        log_error "This script requires apt or apt-get package manager."
        exit 1
    fi
    
    log_success "System compatibility check passed."
}

# Function to clone repository
clone_repository() {
    log "Cloning OpenVPN_XOR_package repository..."
    
    # Clean up any existing installation directory
    if [[ -d "$INSTALL_DIR" ]]; then
        log "Cleaning up existing installation directory..."
        rm -rf "$INSTALL_DIR"
    fi
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Clone repository
    git clone "$REPO_URL" || {
        log_error "Failed to clone repository from $REPO_URL"
        exit 1
    }
    
    cd "$REPO_NAME"
    log_success "Repository cloned successfully to $INSTALL_DIR/$REPO_NAME"
}

# Function to check for and build deb packages
build_or_find_packages() {
    log "Checking for deb packages or source to build..."
    
    # Check if there are pre-built deb packages
    local deb_files=$(find . -name "*.deb" -type f)
    
    if [[ -n "$deb_files" ]]; then
        log "Found pre-built deb packages:"
        echo "$deb_files" | while read -r deb; do
            log "  - $deb"
        done
        return 0
    fi
    
    # Check if there's a debian directory for building packages
    if [[ -d "debian" ]]; then
        log "Found debian packaging directory. Building deb package..."
        
        # Install build dependencies
        if [[ $EUID -eq 0 ]]; then
            apt build-dep -y . || log_warning "Could not install all build dependencies"
        else
            sudo apt build-dep -y . || log_warning "Could not install all build dependencies"
        fi
        
        # Build the package
        dpkg-buildpackage -us -uc -b || {
            log_error "Failed to build deb package"
            exit 1
        }
        
        log_success "Deb package built successfully."
        return 0
    fi
    
    
    # If no packages or build options found
    log_warning "No pre-built packages, debian directory, or build script found."
    log_error "Cannot proceed with package installation without deb packages or build capability."
    exit 1
}

# Function to install deb packages
install_packages() {
    log "Installing OpenVPN XOR deb packages..."
    
    # Find OpenVPN deb package
    local openvpn_deb=$(find . -name "openvpn*.deb" -type f | head -1)
    
    if [[ -z "$openvpn_deb" ]]; then
        log_error "No OpenVPN deb package found in the repository."
        exit 1
    fi
    
    log "Found OpenVPN package: $openvpn_deb"
    
    # Check for dependencies and install them first
    local ssl_packages=$(find . -name "libssl*.deb" -type f)
    local openssl_packages=$(find . -name "openssl*.deb" -type f)
    local multiarch_packages=$(find . -name "multiarch-support*.deb" -type f)
    
    # Install dependencies first
    for pkg in $multiarch_packages $ssl_packages $openssl_packages; do
        if [[ -f "$pkg" ]]; then
            log "Installing dependency: $(basename "$pkg")"
            if [[ $EUID -eq 0 ]]; then
                dpkg -i "$pkg" || {
                    log_warning "Failed to install $pkg with dpkg, trying with apt"
                    apt install -f -y
                    dpkg -i "$pkg" || {
                        log_error "Failed to install dependency $pkg"
                        exit 1
                    }
                }
            else
                sudo dpkg -i "$pkg" || {
                    log_warning "Failed to install $pkg with dpkg, trying with apt"
                    sudo apt install -f -y
                    sudo dpkg -i "$pkg" || {
                        log_error "Failed to install dependency $pkg"
                        exit 1
                    }
                }
            fi
        fi
    done
    
    # Install main OpenVPN package
    log "Installing main OpenVPN XOR package..."
    if [[ $EUID -eq 0 ]]; then
        dpkg -i "$openvpn_deb" || {
            log "Resolving dependencies..."
            dpkg -i "$openvpn_deb" || {
                log_error "Failed to install OpenVPN package"
                exit 1
            }
        }
    else
        sudo dpkg -i "$openvpn_deb" || {
            log "Resolving dependencies..."
            sudo dpkg -i "$openvpn_deb" || {
                log_error "Failed to install OpenVPN package"
                exit 1
            }
        }
    fi
    
    log_success "OpenVPN XOR package installed successfully!"
}

# Function to verify installation
verify_installation() {
    log "Verifying installation..."
    
    if command -v openvpn &> /dev/null; then
        local version=$(openvpn --version 2>&1 | head -1)
        log_success "OpenVPN installed successfully: $version"
        
        # Check if XOR patch is available (look for XOR-related options)
        if openvpn --help 2>&1 | grep -qi "xor"; then
            log_success "XOR functionality appears to be available in this OpenVPN build."
        else
            log_warning "XOR functionality may not be available or detectable via help output."
        fi
    else
        log_error "OpenVPN command not found after installation."
        exit 1
    fi
}

# Function to cleanup
cleanup() {
    log "Cleaning up temporary files..."
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        log "Temporary installation directory removed."
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -k, --keep-files    Keep temporary files after installation"
    echo "  -v, --verbose       Enable verbose output"
    echo ""
    echo "This script automatically installs OpenVPN XOR package from the repository."
    echo "It will clone the repository, check/install dependencies, and install the deb packages."
}

# Main execution function
main() {
    local keep_files=false
    local verbose=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -k|--keep-files)
                keep_files=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                set -x
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log "Starting OpenVPN XOR automatic installation..."
    log "Log file: $LOGFILE"
    
    # Execute installation steps
    check_root
    check_system
    clone_repository
    build_or_find_packages
    install_packages
    verify_installation
    
    if [[ "$keep_files" == "false" ]]; then
        cleanup
    else
        log "Keeping temporary files in $INSTALL_DIR as requested."
    fi
    
    log_success "OpenVPN XOR installation completed successfully!"
    log "You can now use OpenVPN with XOR obfuscation capabilities."
    log "For configuration help, refer to OpenVPN documentation."
}

# Set up signal handlers for cleanup
trap 'log_error "Installation interrupted by user"; cleanup; exit 1' INT TERM

# Run main function
main "$@"
