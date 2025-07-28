#!/bin/bash
# setup-docker-simple.sh - Simplified working version
# Fixes the menu selection bug and provides a reliable deployment experience

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration
readonly CONTAINER_NAME="kifiya-maturity-graph"
readonly IMAGE_NAME="kifiya-maturity-graph:latest"
readonly APP_PORT="9885"

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  INFO:${NC} $1"; }
log_success() { echo -e "${GREEN}✅ SUCCESS:${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠️  WARNING:${NC} $1"; }
log_error() { echo -e "${RED}❌ ERROR:${NC} $1" >&2; }

# Simple error handler
handle_error() {
    local exit_code=$?
    echo -e "\n${RED}💥 ERROR: Command failed with exit code $exit_code${NC}"
    echo -e "${YELLOW}💡 Common solutions:${NC}"
    echo -e "   • Check Docker is running: ${CYAN}docker version${NC}"
    echo -e "   • Free up space: ${CYAN}docker system prune -f${NC}"
    echo -e "   • Check port 9885: ${CYAN}netstat -tlnp | grep 9885${NC}"
    echo -e "   • View logs: ${CYAN}docker logs $CONTAINER_NAME${NC}"
    exit $exit_code
}
trap handle_error ERR

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check Docker installation
    if ! command -v docker &> /dev/null; then
        log_error "Docker not installed!"
        echo -e "\n${WHITE}📦 INSTALL DOCKER:${NC}"
        echo -e "   Ubuntu/Debian: ${CYAN}curl -fsSL https://get.docker.com | sh${NC}"
        echo -e "   Then run: ${CYAN}sudo usermod -aG docker \$USER${NC}"
        echo -e "   Log out and back in, then re-run this script"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon not running!"
        echo -e "\n${WHITE}🔧 START DOCKER:${NC}"
        echo -e "   Linux: ${CYAN}sudo systemctl start docker${NC}"
        echo -e "   Then run: ${CYAN}sudo systemctl enable docker${NC}"
        exit 1
    fi
    
    # Check required files
    local missing_files=()
    [[ ! -f "src/app.py" ]] && missing_files+=("src/app.py")
    [[ ! -f "requirements.txt" ]] && missing_files+=("requirements.txt")
    [[ ! -f "Dockerfile" ]] && missing_files+=("Dockerfile")
    
    if (( ${#missing_files[@]} > 0 )); then
        log_error "Missing required files:"
        printf '   • %s\n' "${missing_files[@]}"
        echo -e "\n${WHITE}📁 Ensure you're in the project directory with all files present${NC}"
        exit 1
    fi
    
    # Check port availability
    if netstat -tlnp 2>/dev/null | grep -q ":$APP_PORT " || lsof -i :$APP_PORT >/dev/null 2>&1; then
        log_warning "Port $APP_PORT appears to be in use"
        read -p "$(echo -e "${WHITE}❓ Continue anyway? (y/N):${NC} ")" -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    log_success "System requirements check passed!"
}

# Build Docker image
build_image() {
    log_info "Building Docker image..."
    
    local verbose="${1:-}"
    
    # Clean up old images if requested
    if [[ "$verbose" == "--force-rebuild" ]]; then
        log_info "Removing existing image for fresh build..."
        docker rmi "$IMAGE_NAME" 2>/dev/null || true
    fi
    
    if [[ "$verbose" == "--verbose" ]] || [[ "$verbose" == "--force-rebuild" ]]; then
        docker build -t "$IMAGE_NAME" .
    else
        echo -e "${CYAN}🔨 Building Docker image...${NC}"
        docker build -t "$IMAGE_NAME" . >/dev/null 2>&1 &
        local build_pid=$!
        
        local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0
        
        while kill -0 $build_pid 2>/dev/null; do
            printf "\r${CYAN}🔨 Building Docker image ${spinner[$i]}${NC}"
            i=$(( (i + 1) % ${#spinner[@]} ))
            sleep 0.2
        done
        
        wait $build_pid
        printf "\r${GREEN}🔨 Docker image built successfully! ✅${NC}\n"
    fi
    
    log_success "Docker image '$IMAGE_NAME' ready!"
}

# Deploy container
deploy_container() {
    log_info "Deploying container..."
    
    # Stop and remove existing container
    if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        log_info "Stopping existing container..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1
    fi
    
    if docker ps -aq -f name="$CONTAINER_NAME" | grep -q .; then
        log_info "Removing existing container..."
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1
    fi
    
    # Start new container
    log_info "Starting new container on port $APP_PORT..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "$APP_PORT:$APP_PORT" \
        "$IMAGE_NAME" >/dev/null
    
    log_success "Container '$CONTAINER_NAME' deployed!"
}

# Deploy with Docker Compose
deploy_with_compose() {
    log_info "Deploying with Docker Compose..."
    
    if [[ ! -f "docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found!"
        return 1
    fi
    
    # Stop existing services
    docker-compose down 2>/dev/null || true
    
    # Start new services
    local verbose="${1:-}"
    if [[ "$verbose" == "--verbose" ]]; then
        docker-compose up -d --build
    else
        echo -e "${CYAN}🚀 Starting services with Docker Compose...${NC}"
        docker-compose up -d --build >/dev/null 2>&1
    fi
    
    log_success "Services deployed with Docker Compose!"
}

# Health check
perform_health_check() {
    log_info "Performing health check..."
    
    local max_attempts=12
    local attempt=1
    local url="http://localhost:$APP_PORT"
    
    while (( attempt <= max_attempts )); do
        printf "\r${CYAN}🏥 Health check (attempt $attempt/$max_attempts)...${NC}"
        
        if curl -sf "$url" >/dev/null 2>&1 || wget -q --spider "$url" >/dev/null 2>&1; then
            printf "\r${GREEN}🏥 Health check passed! Application is responding ✅${NC}\n"
            return 0
        fi
        
        sleep 3
        ((attempt++))
    done
    
    printf "\r${YELLOW}⚠️  Health check timeout${NC}\n"
    log_warning "Application may still be starting up"
    
    # Show container status for debugging
    if docker ps --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
        echo -e "\n${WHITE}📊 Container Status:${NC}"
        docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E "(NAMES|$CONTAINER_NAME)"
        
        echo -e "\n${WHITE}📋 Recent Logs:${NC}"
        docker logs --tail 5 "$CONTAINER_NAME" 2>&1 | sed 's/^/   /' || echo "   No logs available"
    fi
}

# Show deployment menu
show_deployment_menu() {
    echo -e "\n${WHITE}🚀 Choose your deployment method:${NC}"
    echo -e "   ${CYAN}1.${NC} 🐳 Docker Compose ${YELLOW}(Recommended if docker-compose.yml exists)${NC}"
    echo -e "   ${CYAN}2.${NC} 📦 Simple Docker Build ${YELLOW}(Works with just Docker)${NC}"
    echo -e "   ${CYAN}3.${NC} 🔧 Manual Step-by-Step ${YELLOW}(Full control)${NC}"
    echo
    
    while true; do
        read -p "$(echo -e "${WHITE}❓ Enter your choice (1-3):${NC} ")" -r choice
        
        case $choice in
            1|2|3)
                echo "$choice"
                return 0
                ;;
            *)
                log_error "Invalid choice. Please enter 1, 2, or 3"
                ;;
        esac
    done
}

# Show final summary
show_summary() {
    echo -e "\n${GREEN}🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "\n${WHITE}🌐 ACCESS YOUR APPLICATION:${NC}"
    echo -e "   ${CYAN}🔗 Primary URL:    http://localhost:$APP_PORT${NC}"
    echo -e "   ${CYAN}🔗 Alternative:    http://127.0.0.1:$APP_PORT${NC}"
    echo -e "   ${CYAN}🔗 Network Access: http://$(hostname -I | awk '{print $1}'):$APP_PORT${NC}"
    
    echo -e "\n${WHITE}🐳 MANAGE YOUR CONTAINER:${NC}"
    echo -e "   ${CYAN}📊 View live logs:${NC}    docker logs -f $CONTAINER_NAME"
    echo -e "   ${CYAN}🛑 Stop container:${NC}    docker stop $CONTAINER_NAME"
    echo -e "   ${CYAN}▶️  Start container:${NC}   docker start $CONTAINER_NAME"
    echo -e "   ${CYAN}🔄 Restart container:${NC} docker restart $CONTAINER_NAME"
    echo -e "   ${CYAN}🗑️  Remove container:${NC}  docker rm -f $CONTAINER_NAME"
    
    if command -v docker-compose >/dev/null 2>&1 && [[ -f "docker-compose.yml" ]]; then
        echo -e "\n${WHITE}📦 DOCKER COMPOSE COMMANDS:${NC}"
        echo -e "   ${CYAN}📊 View logs:${NC}         docker-compose logs -f"
        echo -e "   ${CYAN}🛑 Stop all:${NC}          docker-compose down"
        echo -e "   ${CYAN}▶️  Start all:${NC}         docker-compose up -d"
        echo -e "   ${CYAN}🔄 Restart:${NC}           docker-compose restart"
        echo -e "   ${CYAN}🔨 Rebuild & restart:${NC} docker-compose up -d --build"
    fi
    
    echo -e "\n${WHITE}💡 HELPFUL TIPS:${NC}"
    echo -e "   • Container auto-restarts on system reboot"
    echo -e "   • Use ${CYAN}docker system prune${NC} to free up disk space"
    echo -e "   • Check container health: ${CYAN}docker inspect $CONTAINER_NAME | grep Health -A 5${NC}"
    
    echo -e "\n${WHITE}🆘 TROUBLESHOOTING:${NC}"
    echo -e "   • App not loading? Wait 1-2 minutes for full startup"
    echo -e "   • Port conflict? Check: ${CYAN}netstat -tlnp | grep $APP_PORT${NC}"
    echo -e "   • View detailed logs: ${CYAN}docker logs $CONTAINER_NAME${NC}"
    echo -e "   • Restart everything: ${CYAN}docker restart $CONTAINER_NAME${NC}"
    
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}✨ Your Kifiya Maturity Dependency Graph is now running! ✨${NC}"
    echo -e "${WHITE}🌟 Open the URL above in your browser to get started! 🌟${NC}"
}

# Parse command line arguments
parse_args() {
    VERBOSE=""
    FORCE_REBUILD=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE="--verbose"
                log_info "Verbose mode enabled"
                shift
                ;;
            -f|--force-rebuild)
                FORCE_REBUILD="--force-rebuild"
                log_info "Force rebuild enabled"
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

# Show help
show_help() {
    echo -e "${WHITE}🐳 Kifiya Docker Setup - Simple & Reliable${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${WHITE}USAGE:${NC} $0 [OPTIONS]"
    echo
    echo -e "${WHITE}OPTIONS:${NC}"
    echo -e "   ${CYAN}-v, --verbose${NC}       Show detailed build output"
    echo -e "   ${CYAN}-f, --force-rebuild${NC} Force rebuild (ignore Docker cache)"
    echo -e "   ${CYAN}-h, --help${NC}          Show this help message"
    echo
    echo -e "${WHITE}EXAMPLES:${NC}"
    echo -e "   ${CYAN}$0${NC}                  # Standard deployment"
    echo -e "   ${CYAN}$0 --verbose${NC}        # Verbose output"
    echo -e "   ${CYAN}$0 --force-rebuild${NC}  # Clean rebuild"
    echo
    echo -e "${WHITE}DESCRIPTION:${NC}"
    echo -e "   Deploys the Kifiya Maturity Dependency Graph using Docker."
    echo -e "   The application will be available at http://localhost:9885"
}

# Main execution
main() {
    # Parse arguments
    parse_args "$@"
    
    # Show header
    echo -e "${WHITE}🎯 Kifiya Maturity Graph - Docker Setup${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📅 $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}📍 $(pwd)${NC}"
    echo -e "${CYAN}👤 $(whoami)${NC}"
    [[ -n "$VERBOSE" ]] && echo -e "${CYAN}🔧 Verbose Mode: ON${NC}"
    [[ -n "$FORCE_REBUILD" ]] && echo -e "${CYAN}🔨 Force Rebuild: ON${NC}"
    
    echo -e "\n${WHITE}🚀 Starting deployment process...${NC}"
    
    # Step 1: Check requirements
    check_requirements
    
    # Step 2: Get deployment method
    local choice=$(show_deployment_menu)
    
    # Step 3: Execute deployment
    case $choice in
        1)
            if command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1; then
                if [[ -f "docker-compose.yml" ]]; then
                    log_info "Selected: Docker Compose deployment"
                    deploy_with_compose "$VERBOSE"
                else
                    log_warning "docker-compose.yml not found, falling back to simple build"
                    build_image "$VERBOSE$FORCE_REBUILD"
                    deploy_container
                fi
            else
                log_warning "Docker Compose not available, using simple build"
                build_image "$VERBOSE$FORCE_REBUILD"
                deploy_container
            fi
            ;;
        2)
            log_info "Selected: Simple Docker build"
            build_image "$VERBOSE$FORCE_REBUILD"
            deploy_container
            ;;
        3)
            log_info "Selected: Manual step-by-step"
            echo -e "\n${WHITE}📋 Manual Commands:${NC}"
            echo -e "   ${CYAN}1. Build:${NC}   docker build -t $IMAGE_NAME ."
            echo -e "   ${CYAN}2. Stop:${NC}    docker stop $CONTAINER_NAME 2>/dev/null || true"
            echo -e "   ${CYAN}3. Remove:${NC}  docker rm $CONTAINER_NAME 2>/dev/null || true"
            echo -e "   ${CYAN}4. Run:${NC}     docker run -d --name $CONTAINER_NAME -p $APP_PORT:$APP_PORT $IMAGE_NAME"
            echo
            read -p "$(echo -e "${WHITE}❓ Execute these commands automatically? (Y/n):${NC} ")" -r
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                build_image "$VERBOSE$FORCE_REBUILD"
                deploy_container
            else
                log_info "Manual mode selected - run the commands above yourself"
                echo -e "${YELLOW}💡 After running manually, access your app at: http://localhost:$APP_PORT${NC}"
                exit 0
            fi
            ;;
    esac
    
    # Step 4: Health check
    perform_health_check
    
    # Step 5: Show summary
    show_summary
}

# Execute main function
main "$@"#!/bin/bash
# setup-docker-fixed.sh - Quick fix for the menu selection bug
# This is a simplified version that fixes the immediate issue

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration
readonly CONTAINER_NAME="kifiya-maturity-graph"
readonly IMAGE_NAME="kifiya-maturity-graph:latest"
readonly APP_PORT="9885"

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  INFO:${NC} $1"; }
log_success() { echo -e "${GREEN}✅ SUCCESS:${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠️  WARNING:${NC} $1"; }
log_error() { echo -e "${RED}❌ ERROR:${NC} $1" >&2; }

# Simple error handler
handle_error() {
    echo -e "\n${RED}💥 ERROR: Something went wrong!${NC}"
    echo -e "${YELLOW}💡 Try running: docker system prune -f${NC}"
    echo -e "${YELLOW}💡 Or run with: $0 --verbose${NC}"
    exit 1
}
trap handle_error ERR

# Check Docker
check_docker() {
    log_info "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker not installed!"
        echo -e "${WHITE}📦 Quick install:${NC} curl -fsSL https://get.docker.com | sh"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon not running!"
        echo -e "${WHITE}🔧 Start Docker:${NC} sudo systemctl start docker"
        exit 1
    fi
    
    log_success "Docker is ready!"
}

# Build image
build_image() {
    log_info "Building Docker image..."
    
    if [[ "$1" == "--verbose" ]]; then
        docker build -t "$IMAGE_NAME" .
    else
        docker build -t "$IMAGE_NAME" . >/dev/null 2>&1 &
        local build_pid=$!
        
        while kill -0 $build_pid 2>/dev/null; do
            printf "\r${CYAN}🔨 Building image... ⏳${NC}"
            sleep 0.5
        done
        wait $build_pid
        printf "\r${GREEN}🔨 Image built successfully! ✅${NC}\n"
    fi
}

# Deploy container
deploy_container() {
    log_info "Deploying container..."
    
    # Clean up existing
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    
    # Run new container
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "$APP_PORT:$APP_PORT" \
        "$IMAGE_NAME"
    
    log_success "Container deployed!"
}

# Health check
health_check() {
    log_info "Performing health check..."
    
    local attempts=0
    local max_attempts=10
    
    while (( attempts < max_attempts )); do
        if curl -sf "http://localhost:$APP_PORT" >/dev/null 2>&1; then
            log_success "Health check passed!"
            return 0
        fi
        
        printf "\r${CYAN}🏥 Waiting for app to start... ($((attempts + 1))/$max_attempts)${NC}"
        sleep 3
        ((attempts++))
    done
    
    printf "\r${YELLOW}⚠️  Health check timeout - app may still be starting${NC}\n"
}

# Show menu and get choice
show_menu() {
    echo -e "\n${WHITE}🚀 Choose deployment method:${NC}"
    echo -e "   ${CYAN}1.${NC} 🐳 Docker Compose (if available)"
    echo -e "   ${CYAN}2.${NC} 📦 Simple Docker Build"
    echo -e "   ${CYAN}3.${NC} 🔧 Manual Commands"
    echo
    
    while true; do
        read -p "$(echo -e "${WHITE}❓ Enter choice (1-3):${NC} ")" choice
        case $choice in
            1|2|3) echo "$choice"; return ;;
            *) log_error "Please enter 1, 2, or 3" ;;
        esac
    done
}

# Main function
main() {
    local verbose=""
    if [[ "${1:-}" == "--verbose" ]]; then
        verbose="--verbose"
    fi
    
    echo -e "${WHITE}🎯 Kifiya Docker Setup${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # System checks
    check_docker
    
    # Get deployment choice
    local choice=$(show_menu)
    
    case $choice in
        1)
            if command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1; then
                log_info "Using Docker Compose..."
                docker-compose down 2>/dev/null || true
                if [[ "$verbose" == "--verbose" ]]; then
                    docker-compose up -d --build
                else
                    docker-compose up -d --build >/dev/null 2>&1
                fi
                log_success "Deployed with Docker Compose!"
            else
                log_warning "Docker Compose not available, using simple build..."
                build_image "$verbose"
                deploy_container
            fi
            ;;
        2)
            log_info "Using simple Docker build..."
            build_image "$verbose"
            deploy_container
            ;;
        3)
            echo -e "\n${WHITE}📋 Manual Commands:${NC}"
            echo -e "   ${CYAN}docker build -t $IMAGE_NAME .${NC}"
            echo -e "   ${CYAN}docker stop $CONTAINER_NAME 2>/dev/null || true${NC}"
            echo -e "   ${CYAN}docker rm $CONTAINER_NAME 2>/dev/null || true${NC}"
            echo -e "   ${CYAN}docker run -d --name $CONTAINER_NAME -p $APP_PORT:$APP_PORT $IMAGE_NAME${NC}"
            echo
            read -p "$(echo -e "${WHITE}❓ Run these automatically? (Y/n):${NC} ")" -r
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                build_image "$verbose"
                deploy_container
            else
                log_info "Manual mode - run the commands above yourself"
                exit 0
            fi
            ;;
    esac
    
    # Health check
    health_check
    
    # Success message
    echo -e "\n${GREEN}🎉 DEPLOYMENT COMPLETED!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "\n${WHITE}🌐 APPLICATION ACCESS:${NC}"
    echo -e "   ${CYAN}🔗 URL: http://localhost:$APP_PORT${NC}"
    echo -e "\n${WHITE}🐳 CONTAINER MANAGEMENT:${NC}"
    echo -e "   ${CYAN}📊 View logs:${NC}     docker logs -f $CONTAINER_NAME"
    echo -e "   ${CYAN}🛑 Stop:${NC}          docker stop $CONTAINER_NAME"
    echo -e "   ${CYAN}▶️  Start:${NC}         docker start $CONTAINER_NAME"
    echo -e "   ${CYAN}🔄 Restart:${NC}       docker restart $CONTAINER_NAME"
    echo -e "\n${WHITE}✨ Your Kifiya app is now running! ✨${NC}"
}

# Help function
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo -e "${WHITE}🐳 Kifiya Docker Setup - Quick Fix Version${NC}"
    echo -e "\n${WHITE}USAGE:${NC} $0 [--verbose]"
    echo -e "\n${WHITE}OPTIONS:${NC}"
    echo -e "   ${CYAN}--verbose${NC}    Show detailed build output"
    echo -e "   ${CYAN}--help${NC}       Show this help message"
    exit 0
fi

# Run main function
main "$@"