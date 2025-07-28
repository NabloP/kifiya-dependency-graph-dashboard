#!/bin/bash
# setup-docker.sh - Enhanced Kifiya Maturity Graph Docker deployment script
# Version: 2.0 - Full featured with comprehensive error handling and user engagement

set -euo pipefail  # Strict error handling

# Color codes for better UX
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Configuration
readonly CONTAINER_NAME="kifiya-maturity-graph"
readonly IMAGE_NAME="kifiya-maturity-graph:latest"
readonly APP_PORT="9885"
readonly COMPOSE_FILE="docker-compose.yml"
readonly DOCKERFILE="Dockerfile"

# Global variables
VERBOSE=false
FORCE_REBUILD=false
SKIP_HEALTH_CHECK=false
USE_COMPOSE=false

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  INFO:${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}❌ ERROR:${NC} $1" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${MAGENTA}🔍 DEBUG:${NC} $1"
    fi
}

log_progress() {
    echo -e "${CYAN}⏳ PROGRESS:${NC} $1"
}

# Enhanced error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    local command="$2"
    
    echo -e "\n${RED}💥 CRITICAL ERROR OCCURRED${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}📍 Location:${NC} Line $line_number"
    echo -e "${WHITE}🔧 Command:${NC} $command"
    echo -e "${WHITE}📊 Exit Code:${NC} $exit_code"
    echo -e "${WHITE}⏰ Time:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    
    case $exit_code in
        1)
            echo -e "${YELLOW}💡 Common Issue:${NC} General error - check command syntax and permissions"
            ;;
        2)
            echo -e "${YELLOW}💡 Common Issue:${NC} Command not found or incorrect usage"
            ;;
        125)
            echo -e "${YELLOW}💡 Docker Issue:${NC} Docker daemon error or container runtime issue"
            ;;
        126)
            echo -e "${YELLOW}💡 Permission Issue:${NC} Command cannot execute (permission denied)"
            ;;
        127)
            echo -e "${YELLOW}💡 Command Issue:${NC} Command not found in PATH"
            ;;
        *)
            echo -e "${YELLOW}💡 Unknown Issue:${NC} Unexpected error occurred"
            ;;
    esac
    
    echo -e "\n${WHITE}🛠️  DEBUGGING STEPS:${NC}"
    echo -e "   1. Check Docker daemon: ${CYAN}docker version${NC}"
    echo -e "   2. Check system resources: ${CYAN}df -h && free -h${NC}"
    echo -e "   3. Check port availability: ${CYAN}netstat -tlnp | grep $APP_PORT${NC}"
    echo -e "   4. View Docker logs: ${CYAN}docker logs $CONTAINER_NAME${NC}"
    echo -e "   5. Run with verbose mode: ${CYAN}$0 --verbose${NC}"
    
    echo -e "\n${WHITE}🆘 NEED HELP?${NC}"
    echo -e "   • Re-run with: ${CYAN}$0 --verbose --force-rebuild${NC}"
    echo -e "   • Check system requirements in README.md"
    echo -e "   • Ensure Docker Desktop is running"
    echo -e "   • Try: ${CYAN}docker system prune -f${NC} to free space"
    
    exit $exit_code
}

# Set up error trapping
trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR

# Progress bar function
show_progress() {
    local duration=$1
    local message=$2
    local interval=0.1
    local elapsed=0
    local progress=0
    
    echo -ne "${CYAN}⏳ $message${NC} ["
    
    while (( $(echo "$elapsed < $duration" | bc -l) )); do
        progress=$(echo "scale=0; ($elapsed / $duration) * 20" | bc -l)
        printf "\r${CYAN}⏳ $message${NC} ["
        
        for ((i=0; i<20; i++)); do
            if (( i < progress )); then
                printf "█"
            else
                printf "░"
            fi
        done
        
        printf "] %d%%" $(echo "scale=0; ($elapsed / $duration) * 100" | bc -l)
        
        sleep $interval
        elapsed=$(echo "$elapsed + $interval" | bc -l)
    done
    
    printf "\r${CYAN}⏳ $message${NC} [████████████████████] 100%%\n"
}

# System requirements check
check_system_requirements() {
    log_progress "Checking system requirements..."
    
    # Check operating system
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        log_debug "Detected Linux system"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        log_debug "Detected macOS system"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        log_debug "Detected Windows system"
    else
        log_warning "Unknown operating system: $OSTYPE"
    fi
    
    # Check available disk space
    local available_space=$(df . | awk 'NR==2 {print $4}')
    local required_space=1048576  # 1GB in KB
    
    if (( available_space < required_space )); then
        log_error "Insufficient disk space. Available: $(( available_space / 1024 ))MB, Required: 1GB"
        echo -e "${YELLOW}💡 Solution:${NC} Free up disk space or run: ${CYAN}docker system prune -a${NC}"
        return 1
    fi
    
    log_debug "Disk space check passed: $(( available_space / 1024 ))MB available"
    
    # Check memory
    if command -v free >/dev/null 2>&1; then
        local available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7}')
        if (( available_memory < 512 )); then
            log_warning "Low memory detected: ${available_memory}MB available"
            echo -e "${YELLOW}💡 Recommendation:${NC} Close other applications to free memory"
        else
            log_debug "Memory check passed: ${available_memory}MB available"
        fi
    fi
    
    log_success "System requirements check completed"
}

# Enhanced Docker installation check
check_docker_installation() {
    log_progress "Verifying Docker installation..."
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed!"
        echo -e "\n${WHITE}📦 INSTALLATION GUIDE:${NC}"
        echo -e "   • Ubuntu/Debian: ${CYAN}curl -fsSL https://get.docker.com | sh${NC}"
        echo -e "   • macOS: Download Docker Desktop from https://docker.com/products/docker-desktop"
        echo -e "   • Windows: Download Docker Desktop from https://docker.com/products/docker-desktop"
        echo -e "\n   After installation, restart your terminal and run this script again."
        return 1
    fi
    
    log_debug "Docker binary found at: $(which docker)"
    
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running!"
        echo -e "\n${WHITE}🔧 SOLUTION:${NC}"
        echo -e "   • Linux: ${CYAN}sudo systemctl start docker${NC}"
        echo -e "   • macOS/Windows: Start Docker Desktop application"
        echo -e "   • Check status: ${CYAN}docker version${NC}"
        return 1
    fi
    
    # Get Docker version info
    local docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    log_debug "Docker daemon version: $docker_version"
    
    # Check Docker Compose
    if command -v docker-compose &> /dev/null; then
        USE_COMPOSE=true
        local compose_version=$(docker-compose version --short 2>/dev/null || echo "unknown")
        log_debug "Docker Compose found (standalone): $compose_version"
    elif docker compose version &> /dev/null 2>&1; then
        USE_COMPOSE=true
        local compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        log_debug "Docker Compose found (plugin): $compose_version"
    else
        USE_COMPOSE=false
        log_warning "Docker Compose not found - using basic Docker commands"
    fi
    
    log_success "Docker installation verified successfully"
}

# Enhanced file validation
validate_project_files() {
    log_progress "Validating project files..."
    
    local missing_files=()
    local critical_files=("src/app.py" "requirements.txt")
    local optional_files=("$DOCKERFILE" "$COMPOSE_FILE" "data/domain_nodes.csv" "data/domain_dependencies.csv")
    
    # Check critical files
    for file in "${critical_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file (CRITICAL)")
        else
            log_debug "Found critical file: $file"
        fi
    done
    
    # Check optional files
    for file in "${optional_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_warning "Optional file missing: $file"
        else
            log_debug "Found optional file: $file"
        fi
    done
    
    # Report missing critical files
    if (( ${#missing_files[@]} > 0 )); then
        log_error "Missing critical project files:"
        printf '%s\n' "${missing_files[@]}" | sed 's/^/   • /'
        echo -e "\n${WHITE}📁 EXPECTED PROJECT STRUCTURE:${NC}"
        echo -e "   your-project/"
        echo -e "   ├── src/"
        echo -e "   │   ├── app.py              ${RED}(REQUIRED)${NC}"
        echo -e "   │   ├── layout.py"
        echo -e "   │   └── callbacks.py"
        echo -e "   ├── data/"
        echo -e "   │   ├── domain_nodes.csv"
        echo -e "   │   └── domain_dependencies.csv"
        echo -e "   ├── requirements.txt        ${RED}(REQUIRED)${NC}"
        echo -e "   ├── Dockerfile"
        echo -e "   └── docker-compose.yml"
        return 1
    fi
    
    # Validate Python app
    if [[ -f "src/app.py" ]]; then
        if ! grep -q "server.*=.*app\.server" "src/app.py"; then
            log_warning "src/app.py may be missing 'server = app.server' line needed for deployment"
        else
            log_debug "Found server export in src/app.py"
        fi
    fi
    
    log_success "Project files validation completed"
}

# Port availability check
check_port_availability() {
    log_progress "Checking port $APP_PORT availability..."
    
    # Check if port is in use
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -q ":$APP_PORT "; then
            log_warning "Port $APP_PORT appears to be in use"
            echo -e "${YELLOW}🔍 Port usage details:${NC}"
            netstat -tlnp 2>/dev/null | grep ":$APP_PORT " | sed 's/^/   /'
            
            read -p "$(echo -e "${WHITE}❓ Continue anyway? This may cause conflicts. (y/N):${NC} ")" -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Deployment cancelled by user"
                exit 0
            fi
        else
            log_debug "Port $APP_PORT is available"
        fi
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -i :$APP_PORT >/dev/null 2>&1; then
            log_warning "Port $APP_PORT appears to be in use"
            echo -e "${YELLOW}🔍 Port usage details:${NC}"
            lsof -i :$APP_PORT | sed 's/^/   /'
        else
            log_debug "Port $APP_PORT is available"
        fi
    else
        log_debug "Cannot check port availability (netstat/lsof not available)"
    fi
    
    log_success "Port availability check completed"
}

# Interactive user input with validation
get_user_choice() {
    local prompt="$1"
    local options=("$@")
    local choice
    
    while true; do
        echo -e "\n${WHITE}$prompt${NC}"
        for i in "${!options[@]}"; do
            if (( i == 0 )); then continue; fi  # Skip the prompt
            echo -e "   ${CYAN}$i.${NC} ${options[$i]}"
        done
        echo
        
        read -p "$(echo -e "${WHITE}❓ Enter your choice (1-$((${#options[@]} - 1))):${NC} ")" -r choice
        
        # Validate input
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < ${#options[@]} )); then
            return $choice
        else
            log_error "Invalid choice. Please enter a number between 1 and $((${#options[@]} - 1))"
        fi
    done
}

# Clean up existing containers
cleanup_existing_container() {
    log_progress "Cleaning up existing containers..."
    
    # Check if container exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_debug "Found existing container: $CONTAINER_NAME"
        
        # Stop container if running
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            log_info "Stopping running container..."
            docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || {
                log_warning "Failed to stop container gracefully, forcing..."
                docker kill "$CONTAINER_NAME" >/dev/null 2>&1 || true
            }
        fi
        
        # Remove container
        log_info "Removing existing container..."
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || {
            log_warning "Failed to remove container"
        }
    else
        log_debug "No existing container found"
    fi
    
    log_success "Container cleanup completed"
}

# Build Docker image with progress
build_docker_image() {
    log_progress "Building Docker image..."
    
    local build_args=()
    
    if [[ "$VERBOSE" == "true" ]]; then
        build_args+=(--progress=plain)
    else
        build_args+=(--quiet)
    fi
    
    if [[ "$FORCE_REBUILD" == "true" ]]; then
        build_args+=(--no-cache)
        log_info "Force rebuild enabled - ignoring cache"
    fi
    
    # Start build process
    log_info "Starting Docker build process..."
    log_debug "Build command: docker build ${build_args[*]} -t $IMAGE_NAME ."
    
    if [[ "$VERBOSE" == "true" ]]; then
        docker build "${build_args[@]}" -t "$IMAGE_NAME" . || {
            log_error "Docker build failed!"
            echo -e "\n${WHITE}🔧 BUILD TROUBLESHOOTING:${NC}"
            echo -e "   • Check Dockerfile syntax"
            echo -e "   • Ensure requirements.txt exists and is valid"
            echo -e "   • Try: ${CYAN}docker system prune -f${NC} to free space"
            echo -e "   • Run with: ${CYAN}$0 --verbose --force-rebuild${NC}"
            return 1
        }
    else
        # Show custom progress for quiet build
        {
            docker build "${build_args[@]}" -t "$IMAGE_NAME" . &
            local build_pid=$!
            
            local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
            local i=0
            
            while kill -0 $build_pid 2>/dev/null; do
                printf "\r${CYAN}🔨 Building Docker image ${spinner[$i]}${NC}"
                i=$(( (i + 1) % ${#spinner[@]} ))
                sleep 0.2
            done
            
            wait $build_pid
            printf "\r${GREEN}🔨 Building Docker image ✅${NC}\n"
        } || {
            log_error "Docker build failed!"
            return 1
        }
    fi
    
    # Verify image was created
    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
        local image_size=$(docker images --format '{{.Size}}' "$IMAGE_NAME")
        log_success "Docker image built successfully (Size: $image_size)"
    else
        log_error "Docker image was not created properly"
        return 1
    fi
}

# Deploy with Docker Compose
deploy_with_compose() {
    log_progress "Deploying with Docker Compose..."
    
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "docker-compose.yml not found!"
        echo -e "${WHITE}💡 Solution:${NC} Create docker-compose.yml or use manual deployment"
        return 1
    fi
    
    # Stop existing services
    log_info "Stopping existing services..."
    docker-compose down 2>/dev/null || true
    
    # Start services
    log_info "Starting services with Docker Compose..."
    if [[ "$VERBOSE" == "true" ]]; then
        docker-compose up -d --build
    else
        docker-compose up -d --build >/dev/null 2>&1 &
        local compose_pid=$!
        
        local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0
        
        while kill -0 $compose_pid 2>/dev/null; do
            printf "\r${CYAN}🚀 Starting services ${spinner[$i]}${NC}"
            i=$(( (i + 1) % ${#spinner[@]} ))
            sleep 0.3
        done
        
        wait $compose_pid
        printf "\r${GREEN}🚀 Starting services ✅${NC}\n"
    fi
    
    log_success "Docker Compose deployment completed"
}

# Deploy with Docker run
deploy_with_docker_run() {
    log_progress "Deploying with Docker run..."
    
    cleanup_existing_container
    
    # Run container
    log_info "Starting new container..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "$APP_PORT:$APP_PORT" \
        "$IMAGE_NAME" || {
        log_error "Failed to start container!"
        echo -e "\n${WHITE}🔧 CONTAINER TROUBLESHOOTING:${NC}"
        echo -e "   • Check if port $APP_PORT is available"
        echo -e "   • Ensure Docker image was built correctly"
        echo -e "   • Try: ${CYAN}docker logs $CONTAINER_NAME${NC}"
        return 1
    }
    
    log_success "Container deployment completed"
}

# Health check with detailed status
perform_health_check() {
    if [[ "$SKIP_HEALTH_CHECK" == "true" ]]; then
        log_info "Skipping health check (--skip-health-check flag used)"
        return
    fi
    
    log_progress "Performing health check..."
    
    local max_attempts=12
    local attempt=1
    local url="http://localhost:$APP_PORT"
    
    log_info "Waiting for application to start..."
    
    while (( attempt <= max_attempts )); do
        printf "\r${CYAN}🏥 Health check attempt $attempt/$max_attempts...${NC}"
        
        if curl -sf "$url" >/dev/null 2>&1 || wget -q --spider "$url" >/dev/null 2>&1; then
            printf "\r${GREEN}🏥 Health check passed! ✅${NC}\n"
            log_success "Application is responding at $url"
            return 0
        fi
        
        sleep 5
        ((attempt++))
    done
    
    printf "\r${RED}🏥 Health check failed! ❌${NC}\n"
    log_warning "Application may not be ready yet"
    
    # Show container status for debugging
    echo -e "\n${WHITE}🔍 CONTAINER STATUS:${NC}"
    if docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -q "$CONTAINER_NAME"; then
        docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | head -1
        docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep "$CONTAINER_NAME"
    else
        echo "   Container not running"
    fi
    
    # Show recent logs
    echo -e "\n${WHITE}📊 RECENT LOGS:${NC}"
    docker logs --tail 10 "$CONTAINER_NAME" 2>&1 | sed 's/^/   /' || echo "   No logs available"
    
    echo -e "\n${YELLOW}💡 TROUBLESHOOTING:${NC}"
    echo -e "   • Wait a few more minutes for startup"
    echo -e "   • Check logs: ${CYAN}docker logs -f $CONTAINER_NAME${NC}"
    echo -e "   • Verify port: ${CYAN}docker port $CONTAINER_NAME${NC}"
    echo -e "   • Manual test: ${CYAN}curl http://localhost:$APP_PORT${NC}"
}

# Display final status and instructions
show_deployment_summary() {
    echo -e "\n${GREEN}🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Application access
    echo -e "\n${WHITE}🌐 APPLICATION ACCESS:${NC}"
    echo -e "   ${CYAN}🔗 URL: http://localhost:$APP_PORT${NC}"
    echo -e "   ${CYAN}🔗 Alternative: http://127.0.0.1:$APP_PORT${NC}"
    
    # Container management
    echo -e "\n${WHITE}🐳 CONTAINER MANAGEMENT:${NC}"
    echo -e "   ${CYAN}📊 View logs:${NC}     docker logs -f $CONTAINER_NAME"
    echo -e "   ${CYAN}🛑 Stop:${NC}          docker stop $CONTAINER_NAME"
    echo -e "   ${CYAN}▶️  Start:${NC}         docker start $CONTAINER_NAME"
    echo -e "   ${CYAN}🔄 Restart:${NC}       docker restart $CONTAINER_NAME"
    echo -e "   ${CYAN}🗑️  Remove:${NC}        docker rm -f $CONTAINER_NAME"
    
    if [[ "$USE_COMPOSE" == "true" && -f "$COMPOSE_FILE" ]]; then
        echo -e "\n${WHITE}📦 DOCKER COMPOSE COMMANDS:${NC}"
        echo -e "   ${CYAN}📊 View logs:${NC}     docker-compose logs -f"
        echo -e "   ${CYAN}🛑 Stop all:${NC}      docker-compose down"
        echo -e "   ${CYAN}▶️  Start all:${NC}     docker-compose up -d"
        echo -e "   ${CYAN}🔄 Restart:${NC}       docker-compose restart"
        echo -e "   ${CYAN}🔨 Rebuild:${NC}       docker-compose up -d --build"
    fi
    
    # System information
    echo -e "\n${WHITE}💻 SYSTEM INFORMATION:${NC}"
    echo -e "   ${CYAN}🏷️  Container:${NC}     $CONTAINER_NAME"
    echo -e "   ${CYAN}🖼️  Image:${NC}         $IMAGE_NAME"
    echo -e "   ${CYAN}🚪 Port:${NC}          $APP_PORT"
    echo -e "   ${CYAN}📁 Working Dir:${NC}   $(pwd)"
    
    # Next steps
    echo -e "\n${WHITE}📋 NEXT STEPS:${NC}"
    echo -e "   1. ${CYAN}Open http://localhost:$APP_PORT in your browser${NC}"
    echo -e "   2. ${CYAN}Explore the Kifiya Maturity Dependency Graph${NC}"
    echo -e "   3. ${CYAN}Check application logs if needed${NC}"
    echo -e "   4. ${CYAN}Refer to documentation for advanced configuration${NC}"
    
    # Support information
    echo -e "\n${WHITE}🆘 NEED HELP?${NC}"
    echo -e "   • Re-run with verbose mode: ${CYAN}$0 --verbose${NC}"
    echo -e "   • Check container status: ${CYAN}docker ps${NC}"
    echo -e "   • View full logs: ${CYAN}docker logs $CONTAINER_NAME${NC}"
    echo -e "   • Free up resources: ${CYAN}docker system prune${NC}"
    
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}✨ Thank you for using the Kifiya Maturity Graph Docker deployment script! ✨${NC}"
}

# Command line argument parsing
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                log_info "Verbose mode enabled"
                shift
                ;;
            -f|--force-rebuild)
                FORCE_REBUILD=true
                log_info "Force rebuild enabled"
                shift
                ;;
            --skip-health-check)
                SKIP_HEALTH_CHECK=true
                log_info "Health check will be skipped"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Help function
show_help() {
    echo -e "${WHITE}🐳 Kifiya Maturity Graph - Docker Setup Script${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${WHITE}USAGE:${NC}"
    echo -e "   $0 [OPTIONS]"
    echo
    echo -e "${WHITE}OPTIONS:${NC}"
    echo -e "   ${CYAN}-v, --verbose${NC}           Enable verbose output with detailed logging"
    echo -e "   ${CYAN}-f, --force-rebuild${NC}     Force rebuild Docker image (ignore cache)"
    echo -e "   ${CYAN}--skip-health-check${NC}     Skip the health check after deployment"
    echo -e "   ${CYAN}-h, --help${NC}              Show this help message"
    echo
    echo -e "${WHITE}EXAMPLES:${NC}"
    echo -e "   ${CYAN}$0${NC}                      # Standard deployment"
    echo -e "   ${CYAN}$0 --verbose${NC}            # Verbose deployment with detailed logs"
    echo -e "   ${CYAN}$0 --force-rebuild${NC}      # Force rebuild Docker image"
    echo -e "   ${CYAN}$0 -v -f${NC}                # Verbose + force rebuild"
    echo
    echo -e "${WHITE}DESCRIPTION:${NC}"
    echo -e "   This script provides a comprehensive Docker deployment solution for the"
    echo -e "   Kifiya Maturity Dependency Graph application with enhanced error handling,"
    echo -e "   progress indicators, and user-friendly debugging information."
}

# Main execution function
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Script header
    echo -e "${WHITE}🎯 Kifiya Maturity Graph - Enhanced Docker Setup${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📅 Date: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}📍 Directory: $(pwd)${NC}"
    echo -e "${CYAN}👤 User: $(whoami)${NC}"
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}🔧 Verbose Mode: ON${NC}"
    fi
    if [[ "$FORCE_REBUILD" == "true" ]]; then
        echo -e "${CYAN}🔨 Force Rebuild: ON${NC}"
    fi
    echo
    
    # Welcome message
    cat << 'EOF'
    ╔══════════════════════════════════════════════════════════════════╗
    ║                    🚀 WELCOME TO KIFIYA SETUP 🚀                  ║
    ║                                                                  ║
    ║  This enhanced script will guide you through deploying your      ║
    ║  Kifiya Maturity Dependency Graph using Docker with:             ║
    ║                                                                  ║
    ║  ✅ Comprehensive error handling & debugging                      ║
    ║  ✅ Interactive progress indicators                               ║
    ║  ✅ Detailed system checks & validation                          ║
    ║  ✅ Multiple deployment options                                   ║
    ║  ✅ Health monitoring & status reporting                         ║
    ║                                                                  ║
    ╚══════════════════════════════════════════════════════════════════╝
EOF
    
    echo
    read -p "$(echo -e "${WHITE}🚀 Press Enter to begin the setup process...${NC}")" -r
    echo
    
    # Execute setup steps
    log_info "Starting comprehensive deployment process..."
    
    # Step 1: System requirements
    check_system_requirements
    
    # Step 2: Docker installation
    check_docker_installation
    
    # Step 3: Project files validation
    validate_project_files
    
    # Step 4: Port availability
    check_port_availability
    
    # Step 5: Get user deployment preference
    local deployment_options=(
        "Choose your deployment method:"
        "🐳 Docker Compose (Recommended - Full orchestration)"
        "📦 Docker Build Script (Simple automated build)"
        "🔧 Manual Docker Commands (Step-by-step control)"
        "ℹ️  Show detailed comparison of methods"
    )
    
    get_user_choice "${deployment_options[@]}"
    local choice=$?
    
    case $choice in
        1)
            if [[ "$USE_COMPOSE" == "true" ]]; then
                log_info "User selected: Docker Compose deployment"
                build_docker_image
                deploy_with_compose
            else
                log_error "Docker Compose not available!"
                log_info "Falling back to manual Docker commands..."
                build_docker_image
                deploy_with_docker_run
            fi
            ;;
        2)
            log_info "User selected: Docker Build Script"
            build_docker_image
            deploy_with_docker_run
            ;;
        3)
            log_info "User selected: Manual Docker Commands"
            echo -e "\n${WHITE}📋 MANUAL DEPLOYMENT STEPS:${NC}"
            echo -e "   1. Build image: ${CYAN}docker build -t $IMAGE_NAME .${NC}"
            echo -e "   2. Stop existing: ${CYAN}docker stop $CONTAINER_NAME 2>/dev/null || true${NC}"
            echo -e "   3. Remove existing: ${CYAN}docker rm $CONTAINER_NAME 2>/dev/null || true${NC}"
            echo -e "   4. Run container: ${CYAN}docker run -d --name $CONTAINER_NAME -p $APP_PORT:$APP_PORT $IMAGE_NAME${NC}"
            echo
            read -p "$(echo -e "${WHITE}❓ Execute these commands automatically? (Y/n):${NC} ")" -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                build_docker_image
                deploy_with_docker_run
            else
                log_info "Manual deployment cancelled by user"
                exit 0
            fi
            ;;
        4)
            echo -e "\n${WHITE}📊 DEPLOYMENT METHOD COMPARISON:${NC}"
            echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            
            echo -e "\n${CYAN}🐳 Docker Compose:${NC}"
            echo -e "   ✅ Easiest to manage and update"
            echo -e "   ✅ Built-in health checks and restart policies" 
            echo -e "   ✅ Easy to scale or add additional services"
            echo -e "   ✅ Configuration stored in docker-compose.yml"
            echo -e "   ❌ Requires docker-compose to be installed"
            
            echo -e "\n${CYAN}📦 Build Script:${NC}"
            echo -e "   ✅ Simple automated process"
            echo -e "   ✅ Works with just Docker (no compose needed)"
            echo -e "   ✅ Good for single container deployments"
            echo -e "   ❌ Manual management for updates"
            echo -e "   ❌ No built-in service orchestration"
            
            echo -e "\n${CYAN}🔧 Manual Commands:${NC}"
            echo -e "   ✅ Full control over each step"
            echo -e "   ✅ Best for learning and troubleshooting"
            echo -e "   ✅ Works in any Docker environment"
            echo -e "   ❌ More steps to remember"
            echo -e "   ❌ Prone to user error"
            
            echo
            read -p "$(echo -e "${WHITE}🔄 Return to menu? (Y/n):${NC} ")" -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                main "$@"  # Restart the selection process
                return
            else
                log_info "Deployment cancelled by user"
                exit 0
            fi
            ;;
    esac
    
    # Step 6: Health check
    perform_health_check
    
    # Step 7: Final summary
    show_deployment_summary
}

# Execute main function with all arguments
main "$@"