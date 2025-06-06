#!/bin/bash

# Phoenix Deployment Cleanup Script
# Removes temporary files and provides options for cleanup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Clean temporary deployment files
clean_temp_files() {
    log_info "Cleaning temporary deployment files..."
    
    local files_cleaned=0
    
    if [[ -f "startup-script-deploy.sh" ]]; then
        rm -f "startup-script-deploy.sh"
        log_info "Removed startup-script-deploy.sh"
        ((files_cleaned++))
    fi
    
    # Clean any other temporary files
    rm -f *.tmp *.temp
    
    if [[ $files_cleaned -gt 0 ]]; then
        log_info "Cleaned $files_cleaned temporary file(s)"
    else
        log_info "No temporary files to clean"
    fi
}

# Show help
show_help() {
    echo "Phoenix Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  temp     Clean temporary deployment files"
    echo "  help     Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 temp    # Clean temporary files"
}

# Main function
main() {
    case "${1:-temp}" in
        temp)
            clean_temp_files
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@" 