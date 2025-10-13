#!/bin/bash

# ==============================================================================
# Script: Techposts Raspberry Pi Cloudflare Tunnel Website Hosting Setup
# Description: Automated WordPress hosting with Cloudflare Tunnel (Robust Version)
#              Auto-detects existing installations, handles port conflicts,
#              and includes comprehensive error recovery
# Version: 2.0 (Robust Edition)
# ==============================================================================

set -e  # Exit on any error (will be trapped)

# --- Color Definitions ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_MAGENTA='\033[0;35m'
C_CYAN='\033[0;36m'

# --- Global Variables ---
SCRIPT_VERSION="2.0"
LOG_FILE="/var/log/cloudflare-tunnel-setup.log"
STATE_FILE="/root/.cloudflare_tunnel_state"
BACKUP_DIR="/root/cloudflare_tunnel_backups"

# --- Helper Functions ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

print_info() {
    echo -e "${C_BLUE}ℹ INFO: $1${C_RESET}"
    log "INFO: $1"
}

print_success() {
    echo -e "${C_GREEN}✓ SUCCESS: $1${C_RESET}"
    log "SUCCESS: $1"
}

print_warning() {
    echo -e "${C_YELLOW}⚠ WARNING: $1${C_RESET}"
    log "WARNING: $1"
}

print_error() {
    echo -e "${C_RED}✗ ERROR: $1${C_RESET}" >&2
    log "ERROR: $1"
}

print_step() {
    echo -e "\n${C_MAGENTA}▶ STEP $1: $2${C_RESET}"
    echo -e "${C_MAGENTA}$(printf '─%.0s' {1..70})${C_RESET}"
    log "STEP $1: $2"
}

print_section() {
    echo -e "\n${C_CYAN}╔══════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║  $1${C_RESET}"
    echo -e "${C_CYAN}╚══════════════════════════════════════════════════════════════╝${C_RESET}\n"
}

# Error handler with cleanup
error_exit() {
    print_error "$1"
    print_error "Installation failed at step: $(cat $STATE_FILE 2>/dev/null || echo 'unknown')"
    log "FATAL: $1"

    echo
    print_info "Log file location: $LOG_FILE"
    echo
    read -p "Would you like to see the error log? (y/N): " show_log
    if [[ "$show_log" =~ ^[Yy]$ ]]; then
        tail -n 50 "$LOG_FILE"
    fi

    exit 1
}

# Trap errors
trap 'error_exit "An unexpected error occurred at line $LINENO"' ERR

# Save state
save_state() {
    echo "$1" > "$STATE_FILE"
    log "State saved: $1"
}

# Validate domain name format
validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

# Create backup of file
backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        local backup_name="$(basename $file).backup.$(date +%s)"
        cp "$file" "$BACKUP_DIR/$backup_name"
        print_info "Backed up: $file → $BACKUP_DIR/$backup_name"
    fi
}

# Check if port is in use and attempt to free it
check_and_free_port() {
    local port=$1
    local service_name=$2

    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_warning "Port $port is already in use"

        # Get process using the port
        local pid=$(lsof -Pi :$port -sTCP:LISTEN -t)
        local process=$(ps -p $pid -o comm= 2>/dev/null || echo "unknown")

        print_info "Process using port $port: $process (PID: $pid)"

        # If it's the same service we're installing, stop it
        if [[ "$process" == *"$service_name"* ]] || [[ "$service_name" == "apache" && "$process" == *"apache"* ]]; then
            print_info "Stopping existing $service_name service..."
            systemctl stop $service_name 2>/dev/null || true
            killall -9 $process 2>/dev/null || true
            sleep 2

            if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
                print_error "Failed to free port $port"
                return 1
            else
                print_success "Port $port freed successfully"
                return 0
            fi
        else
            echo
            print_warning "Another process is using port $port"
            read -p "Attempt to kill the process and continue? (y/N): " kill_choice
            if [[ "$kill_choice" =~ ^[Yy]$ ]]; then
                kill -9 $pid 2>/dev/null || true
                sleep 2
                if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
                    print_error "Failed to free port $port"
                    return 1
                else
                    print_success "Port $port freed successfully"
                    return 0
                fi
            else
                return 1
            fi
        fi
    fi
    return 0
}

# Detect existing installations
detect_existing_installation() {
    print_section "DETECTING EXISTING INSTALLATIONS"

    local has_apache=false
    local has_mysql=false
    local has_wordpress=false
    local has_cloudflared=false
    local has_tunnel=false

    # Check Apache
    if systemctl is-active --quiet apache2 2>/dev/null || command -v apache2 >/dev/null 2>&1; then
        has_apache=true
        print_warning "Apache is already installed"
    fi

    # Check MySQL/MariaDB
    if systemctl is-active --quiet mariadb 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null; then
        has_mysql=true
        print_warning "MySQL/MariaDB is already installed"
    fi

    # Check WordPress
    if [[ -f "/var/www/html/wp-config.php" ]]; then
        has_wordpress=true
        print_warning "WordPress installation detected at /var/www/html"
    fi

    # Check cloudflared
    if command -v cloudflared >/dev/null 2>&1; then
        has_cloudflared=true
        print_warning "Cloudflared is already installed"

        # Check for existing tunnels
        if cloudflared tunnel list 2>/dev/null | grep -v "^ID" | grep -v "^$" >/dev/null 2>&1; then
            has_tunnel=true
            print_warning "Existing Cloudflare tunnels detected:"
            cloudflared tunnel list 2>/dev/null | grep -v "^$"
        fi
    fi

    # If anything exists, ask user how to proceed
    if [[ "$has_apache" == true ]] || [[ "$has_mysql" == true ]] || [[ "$has_wordpress" == true ]] || [[ "$has_cloudflared" == true ]]; then
        echo
        print_warning "Existing installation(s) detected!"
        echo
        echo "Options:"
        echo "  1. Continue and use existing components (recommended)"
        echo "  2. Reinstall all components (will backup existing data)"
        echo "  3. Exit and manually clean up"
        echo
        read -p "Choose option (1-3): " install_choice

        case $install_choice in
            1)
                print_info "Continuing with existing components..."
                export SKIP_APACHE=$has_apache
                export SKIP_MYSQL=$has_mysql
                export SKIP_WORDPRESS=$has_wordpress
                export SKIP_CLOUDFLARED=$has_cloudflared
                ;;
            2)
                print_info "Will reinstall components with backup..."
                if [[ "$has_wordpress" == true ]]; then
                    backup_wordpress
                fi
                export SKIP_APACHE=false
                export SKIP_MYSQL=false
                export SKIP_WORDPRESS=false
                export SKIP_CLOUDFLARED=false
                ;;
            3)
                print_info "Installation cancelled by user"
                exit 0
                ;;
            *)
                error_exit "Invalid option selected"
                ;;
        esac
    else
        print_success "No existing installations detected - proceeding with fresh install"
        export SKIP_APACHE=false
        export SKIP_MYSQL=false
        export SKIP_WORDPRESS=false
        export SKIP_CLOUDFLARED=false
    fi
}

# Backup WordPress
backup_wordpress() {
    print_info "Backing up existing WordPress installation..."

    mkdir -p "$BACKUP_DIR"
    local backup_date=$(date +%Y%m%d_%H%M%S)

    # Backup files
    if [[ -d "/var/www/html" ]]; then
        print_info "Backing up WordPress files..."
        tar -czf "$BACKUP_DIR/wordpress_files_$backup_date.tar.gz" -C /var/www/html . 2>/dev/null || true
    fi

    # Backup database if MySQL is running
    if systemctl is-active --quiet mariadb 2>/dev/null; then
        print_info "Backing up WordPress database..."

        # Try to find wp-config.php to get DB credentials
        if [[ -f "/var/www/html/wp-config.php" ]]; then
            local db_name=$(grep "DB_NAME" /var/www/html/wp-config.php | cut -d "'" -f 4)
            local db_user=$(grep "DB_USER" /var/www/html/wp-config.php | cut -d "'" -f 4)
            local db_pass=$(grep "DB_PASSWORD" /var/www/html/wp-config.php | cut -d "'" -f 4)

            if [[ -n "$db_name" ]]; then
                mysqldump -u "$db_user" -p"$db_pass" "$db_name" > "$BACKUP_DIR/wordpress_db_$backup_date.sql" 2>/dev/null || true
            fi
        fi
    fi

    print_success "Backup completed: $BACKUP_DIR/"
}

# Clean up broken repositories
cleanup_broken_repos() {
    print_info "Checking for broken repositories..."

    local update_output=$(mktemp)
    apt-get update > "$update_output" 2>&1 || true

    if grep -qi "does not have a Release file\|404\|failed to fetch\|couldn't be accessed" "$update_output"; then
        print_warning "Detected broken repositories. Attempting automatic fix..."

        # Create backup
        local backup_dir="/etc/apt/sources.list.d.backup.$(date +%s)"
        if [ -d "/etc/apt/sources.list.d" ]; then
            cp -r /etc/apt/sources.list.d "$backup_dir" 2>/dev/null || true
        fi

        # Backup main sources.list
        backup_file "/etc/apt/sources.list"

        # Comment out problematic entries
        if grep -qi "docker" "$update_output"; then
            find /etc/apt/sources.list.d/ -name "*docker*" -type f -exec rm -f {} \; 2>/dev/null || true
            sed -i.bak '/download.docker.com/s/^/#/' /etc/apt/sources.list 2>/dev/null || true
        fi

        # Remove other common broken repos
        find /etc/apt/sources.list.d/ -type f -name "*.list" | while read repo_file; do
            if grep -f "$repo_file" "$update_output" >/dev/null 2>&1; then
                print_info "Removing broken repo: $(basename $repo_file)"
                mv "$repo_file" "$repo_file.disabled" 2>/dev/null || true
            fi
        done

        # Try update again
        print_info "Retrying package update..."
        if apt-get update > /dev/null 2>&1; then
            print_success "Repository issues resolved!"
        else
            print_warning "Some repository issues remain, but continuing..."
        fi
    fi

    rm -f "$update_output"
    return 0
}

# Detect architecture
detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        aarch64|arm64) echo "arm64" ;;
        armv7l|armv6l) echo "arm" ;;
        x86_64) echo "amd64" ;;
        *) error_exit "Unsupported architecture: $arch" ;;
    esac
}

# Detect PHP version
detect_available_php() {
    for version in 8.3 8.2 8.1 8.0 7.4; do
        if apt-cache show php${version} >/dev/null 2>&1; then
            echo "$version"
            return 0
        fi
    done
    echo "8.1"  # fallback
}

# Check internet connection with retry
check_internet() {
    print_info "Checking internet connection..."
    local retries=3
    local count=0

    while [ $count -lt $retries ]; do
        if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
            print_success "Internet connection verified."
            return 0
        fi
        count=$((count + 1))
        if [ $count -lt $retries ]; then
            print_warning "Internet check failed, retrying... ($count/$retries)"
            sleep 2
        fi
    done

    error_exit "No internet connection detected. Please connect to the internet and try again."
}

# Check required commands
check_required_commands() {
    print_info "Checking required commands..."
    local missing_commands=()

    for cmd in wget curl tar gzip hostname awk sed grep; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -gt 0 ]; then
        print_warning "Missing commands: ${missing_commands[*]}"
        print_info "Installing missing packages..."

        apt-get update >/dev/null 2>&1 || true

        for cmd in "${missing_commands[@]}"; do
            case $cmd in
                wget) apt-get install -y wget ;;
                curl) apt-get install -y curl ;;
                tar|gzip) apt-get install -y tar gzip ;;
                *) print_warning "Cannot auto-install: $cmd" ;;
            esac
        done
    fi

    print_success "All required commands available."
}

# Check disk space
check_disk_space() {
    print_info "Checking available disk space..."

    local available=$(df / | tail -1 | awk '{print $4}')
    local required=2097152  # 2GB in KB

    if [ "$available" -lt "$required" ]; then
        print_warning "Low disk space detected: $(($available / 1024))MB available"
        print_warning "Recommended: At least 2GB free space"
        read -p "Continue anyway? (y/N): " continue_anyway
        [[ ! "$continue_anyway" =~ ^[Yy]$ ]] && error_exit "Installation cancelled due to low disk space"
    else
        print_success "Sufficient disk space available: $(($available / 1024))MB"
    fi
}

# Smart package installation
smart_install() {
    local package=$1
    local max_retries=3
    local retry_count=0

    # Check if already installed
    if dpkg -l | grep -q "^ii  $package "; then
        print_info "$package is already installed"
        return 0
    fi

    while [ $retry_count -lt $max_retries ]; do
        print_info "Installing $package (attempt $((retry_count + 1))/$max_retries)..."

        if DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" 2>&1 | tee -a "$LOG_FILE"; then
            print_success "$package installed successfully"
            return 0
        fi

        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            print_warning "Installation failed, retrying after apt-get update..."
            apt-get update >/dev/null 2>&1 || true
            sleep 2
        fi
    done

    print_error "Failed to install $package after $max_retries attempts"
    return 1
}

# --- Root User Check ---
if [[ $EUID -ne 0 ]]; then
   error_exit "This script must be run as root. Please use 'sudo bash $0'"
fi

# Initialize log file
mkdir -p "$(dirname $LOG_FILE)"
echo "=== Cloudflare Tunnel Setup Started: $(date) ===" >> "$LOG_FILE"

# --- Script Start ---
clear
echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${C_YELLOW}    🌐 Cloudflare Tunnel Setup - Robust Edition v${SCRIPT_VERSION} 🔒      ${C_RESET}"
echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo
print_info "Enhanced with:"
echo "  • Automatic detection of existing installations"
echo "  • Port conflict resolution"
echo "  • Automatic backup and recovery"
echo "  • Comprehensive error handling"
echo "  • Installation state tracking"
echo

# Pre-flight checks
check_internet
check_required_commands
check_disk_space

# Detect existing installations
detect_existing_installation

# --- Prerequisites Check ---
print_section "PREREQUISITES - READ CAREFULLY!"
echo -e "${C_YELLOW}Before you continue, you MUST:${C_RESET}"
echo
echo "  1. ✅ Have a domain name (required for Cloudflare Tunnel)"
echo "  2. ✅ Have a Cloudflare account (free) - https://dash.cloudflare.com/sign-up"
echo "  3. ✅ Have your domain's nameservers pointing to Cloudflare"
echo
read -p "Have you completed all prerequisites? (y/N): " prereq_check
if [[ ! "$prereq_check" =~ ^[Yy]$ ]]; then
    print_error "Please complete the prerequisites and run the script again."
    exit 0
fi

read -p "Continue with installation? (y/N): " choice
if [[ ! "$choice" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# Get system info
LOCAL_IP=$(hostname -I | awk '{print $1}')
[[ -z "$LOCAL_IP" ]] && error_exit "Could not determine local IP address."

ARCH=$(detect_architecture)
print_success "Architecture: $ARCH, Local IP: $LOCAL_IP"

# --- Domain Configuration ---
print_section "DOMAIN CONFIGURATION"

while true; do
    read -p "Enter your domain name: " DOMAIN_NAME
    [[ -z "$DOMAIN_NAME" ]] && { print_error "Domain name cannot be empty."; continue; }
    validate_domain "$DOMAIN_NAME" || { print_error "Invalid domain format."; continue; }

    # Check Cloudflare nameservers
    print_info "Checking Cloudflare configuration..."

    # Ensure dig is available
    if ! command -v dig >/dev/null 2>&1; then
        print_info "Installing dnsutils for domain verification..."
        apt-get install -y dnsutils >/dev/null 2>&1 || {
            print_warning "Could not install dig command - skipping DNS verification"
            break
        }
    fi

    if dig NS "$DOMAIN_NAME" +short 2>/dev/null | grep -qi cloudflare; then
        print_success "Domain is configured with Cloudflare!"
        break
    else
        print_warning "Domain doesn't appear to use Cloudflare nameservers."
        read -p "Continue anyway? (y/N): " ns_choice
        [[ "$ns_choice" =~ ^[Yy]$ ]] && break
    fi
done

# --- WordPress Configuration ---
print_section "WORDPRESS CONFIGURATION"

read -p "Database name (default: wordpress): " DB_NAME
DB_NAME=${DB_NAME:-wordpress}

read -p "Database username (default: wpuser): " DB_USER
DB_USER=${DB_USER:-wpuser}

while true; do
    read -sp "Database password (min 12 chars): " DB_PASS
    echo
    [[ ${#DB_PASS} -lt 12 ]] && { print_error "Password must be at least 12 characters."; continue; }
    read -sp "Confirm password: " DB_PASS_CONFIRM
    echo
    [[ "$DB_PASS" != "$DB_PASS_CONFIRM" ]] && { print_error "Passwords do not match."; continue; }
    break
done

read -p "Tunnel name (default: $DOMAIN_NAME): " TUNNEL_NAME
TUNNEL_NAME=$(echo "${TUNNEL_NAME:-$DOMAIN_NAME}" | tr '.' '-' | tr -cd '[:alnum:]-')

# --- Configuration Summary ---
print_section "CONFIGURATION SUMMARY"
echo -e "Domain:           ${C_GREEN}$DOMAIN_NAME${C_RESET}"
echo -e "Local IP:         ${C_GREEN}$LOCAL_IP${C_RESET}"
echo -e "Database Name:    ${C_GREEN}$DB_NAME${C_RESET}"
echo -e "Database User:    ${C_GREEN}$DB_USER${C_RESET}"
echo -e "Tunnel Name:      ${C_GREEN}$TUNNEL_NAME${C_RESET}"
echo
read -p "Proceed with installation? (y/N): " confirm
[[ ! "$confirm" =~ ^[Yy]$ ]] && error_exit "Installation cancelled by user."

# ============================================================================
# INSTALLATION STEPS
# ============================================================================

# --- STEP 1: Update System ---
save_state "system_update"
print_step "1" "Updating System Packages"

cleanup_broken_repos
print_info "Upgrading system packages..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y || print_warning "Some packages failed to upgrade"
print_success "System updated."

# --- STEP 2: Install Apache ---
if [[ "$SKIP_APACHE" != true ]]; then
    save_state "apache_install"
    print_step "2" "Installing Apache Web Server"

    check_and_free_port 80 "apache2" || error_exit "Cannot free port 80"
    check_and_free_port 443 "apache2" || error_exit "Cannot free port 443"

    smart_install apache2 || error_exit "Failed to install Apache"

    a2enmod rewrite 2>/dev/null || true
    a2enmod headers 2>/dev/null || true

    systemctl enable apache2
    systemctl restart apache2
    sleep 2

    if curl -s http://localhost >/dev/null 2>&1; then
        print_success "Apache installed and verified."
    else
        print_warning "Apache may not be responding correctly."
    fi
else
    print_step "2" "Skipping Apache (already installed)"
    systemctl restart apache2 2>/dev/null || true
fi

# --- STEP 3: Install PHP ---
save_state "php_install"
print_step "3" "Installing PHP"

PHP_VERSION=$(detect_available_php)
print_info "Installing PHP $PHP_VERSION..."

PHP_PACKAGES=(
    "php${PHP_VERSION}"
    "libapache2-mod-php${PHP_VERSION}"
    "php${PHP_VERSION}-mysql"
    "php${PHP_VERSION}-curl"
    "php${PHP_VERSION}-gd"
    "php${PHP_VERSION}-mbstring"
    "php${PHP_VERSION}-xml"
    "php${PHP_VERSION}-xmlrpc"
    "php${PHP_VERSION}-zip"
    "php${PHP_VERSION}-intl"
)

for pkg in "${PHP_PACKAGES[@]}"; do
    smart_install "$pkg" || print_warning "Failed to install $pkg (continuing...)"
done

print_success "PHP $PHP_VERSION installed."

# Optimize PHP config
PHP_INI="/etc/php/${PHP_VERSION}/apache2/php.ini"
if [[ -f "$PHP_INI" ]]; then
    backup_file "$PHP_INI"
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
    sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI"
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
    sed -i 's/memory_limit = .*/memory_limit = 256M/' "$PHP_INI"
    print_success "PHP optimized for WordPress."
fi

systemctl restart apache2

# --- STEP 4: Install MariaDB ---
if [[ "$SKIP_MYSQL" != true ]]; then
    save_state "mariadb_install"
    print_step "4" "Installing MariaDB"

    check_and_free_port 3306 "mariadb" || error_exit "Cannot free port 3306"

    smart_install mariadb-server || error_exit "Failed to install MariaDB"
    smart_install mariadb-client || error_exit "Failed to install MariaDB client"

    systemctl enable mariadb
    systemctl start mariadb
    sleep 2

    print_success "MariaDB installed and running."
else
    print_step "4" "Skipping MariaDB (already installed)"
    systemctl start mariadb 2>/dev/null || true
fi

# --- STEP 5: Secure MariaDB & Create Database ---
save_state "mariadb_config"
print_step "5" "Configuring MariaDB"

# Check if root password already exists
if [[ -f "/root/.mysql_root_password" ]]; then
    MYSQL_ROOT_PASS=$(cat /root/.mysql_root_password)
    print_info "Using existing MySQL root password"

    # Verify the password works
    if ! mysql -u root -p"$MYSQL_ROOT_PASS" -e "SELECT 1;" >/dev/null 2>&1; then
        print_warning "Stored password doesn't work, attempting to reset..."

        # Try without password (fresh install)
        if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
            MYSQL_ROOT_PASS=$(openssl rand -base64 32)
            mysql -u root <<MYSQL_SECURE
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASS';
FLUSH PRIVILEGES;
MYSQL_SECURE
            echo "$MYSQL_ROOT_PASS" > /root/.mysql_root_password
            chmod 600 /root/.mysql_root_password
            print_success "MySQL root password set."
        else
            error_exit "Cannot access MySQL. Please reset root password manually: sudo mysql_secure_installation"
        fi
    fi
else
    MYSQL_ROOT_PASS=$(openssl rand -base64 32)

    # Try to secure MariaDB - first attempt without password (fresh install)
    if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
        print_info "Securing fresh MariaDB installation..."
        mysql -u root <<MYSQL_SECURE
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASS';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
MYSQL_SECURE
        echo "$MYSQL_ROOT_PASS" > /root/.mysql_root_password
        chmod 600 /root/.mysql_root_password
        print_success "MariaDB secured."
    else
        # Try with sudo (unix_socket auth)
        print_info "Attempting to secure MariaDB with sudo access..."
        if sudo mysql -u root <<MYSQL_SECURE 2>/dev/null
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASS';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
MYSQL_SECURE
        then
            echo "$MYSQL_ROOT_PASS" > /root/.mysql_root_password
            chmod 600 /root/.mysql_root_password
            print_success "MariaDB secured."
        else
            error_exit "Cannot access MySQL. Please run: sudo mysql_secure_installation"
        fi
    fi
fi

# Create WordPress database
print_info "Creating WordPress database..."
mysql -u root -p"$MYSQL_ROOT_PASS" <<MYSQL_DB
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_DB

print_success "WordPress database created."

# --- STEP 6: Install WordPress ---
if [[ "$SKIP_WORDPRESS" != true ]] || [[ ! -f "/var/www/html/wp-config.php" ]]; then
    save_state "wordpress_install"
    print_step "6" "Installing WordPress"

    WEB_ROOT="/var/www/html"
    cd "$WEB_ROOT"

    # Backup existing content
    if ls -A "$WEB_ROOT" 2>/dev/null | grep -v "^lost+found$" >/dev/null; then
        print_info "Backing up existing web content..."
        mkdir -p "$BACKUP_DIR"

        # Create backup with better error handling
        cd "$WEB_ROOT"
        if tar -czf "$BACKUP_DIR/www_backup_$(date +%s).tar.gz" . 2>/dev/null; then
            print_success "Backup created successfully"

            # Clean directory but keep hidden files initially
            find . -mindepth 1 ! -name 'lost+found' -delete 2>/dev/null || {
                print_warning "Could not delete some files, trying with elevated permissions..."
                rm -rf ./* 2>/dev/null || true
                rm -rf ./.* 2>/dev/null || true
            }
        else
            print_warning "Backup failed, but continuing..."
            rm -rf ./* 2>/dev/null || true
        fi
    fi

    # Download WordPress with retry logic
    print_info "Downloading WordPress..."
    local download_success=false
    local download_attempts=0
    local max_download_attempts=3

    while [ $download_attempts -lt $max_download_attempts ] && [ "$download_success" = false ]; do
        download_attempts=$((download_attempts + 1))
        print_info "Download attempt $download_attempts/$max_download_attempts..."

        if wget -q --timeout=30 --tries=1 https://wordpress.org/latest.tar.gz 2>/dev/null; then
            download_success=true
            print_success "WordPress downloaded successfully"
        elif [ $download_attempts -lt $max_download_attempts ]; then
            print_warning "Download failed, retrying..."
            sleep 2
        fi
    done

    [ "$download_success" = false ] && error_exit "Failed to download WordPress after $max_download_attempts attempts"

    print_info "Extracting WordPress..."
    if tar -xzf latest.tar.gz 2>/dev/null; then
        if [ -d "wordpress" ]; then
            # Move files using rsync if available, otherwise use mv
            if command -v rsync >/dev/null 2>&1; then
                rsync -a wordpress/ ./ 2>/dev/null || mv wordpress/* ./ 2>/dev/null
            else
                mv wordpress/* ./ 2>/dev/null || true
            fi
            rm -rf wordpress latest.tar.gz
            print_success "WordPress extracted successfully"
        else
            error_exit "WordPress directory not found after extraction"
        fi
    else
        error_exit "Failed to extract WordPress"
    fi

    # Configure wp-config.php
    print_info "Configuring WordPress..."
    cp wp-config-sample.php wp-config.php

    sed -i "s/database_name_here/$DB_NAME/" wp-config.php
    sed -i "s/username_here/$DB_USER/" wp-config.php
    sed -i "s/password_here/$DB_PASS/" wp-config.php

    # Add security salts
    print_info "Generating security keys..."
    SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)

    # Remove old salt definitions
    sed -i "/define( *'AUTH_KEY'/d" wp-config.php
    sed -i "/define( *'SECURE_AUTH_KEY'/d" wp-config.php
    sed -i "/define( *'LOGGED_IN_KEY'/d" wp-config.php
    sed -i "/define( *'NONCE_KEY'/d" wp-config.php
    sed -i "/define( *'AUTH_SALT'/d" wp-config.php
    sed -i "/define( *'SECURE_AUTH_SALT'/d" wp-config.php
    sed -i "/define( *'LOGGED_IN_SALT'/d" wp-config.php
    sed -i "/define( *'NONCE_SALT'/d" wp-config.php

    # Insert new salts
    awk -v salts="$SALTS" '/stop editing/ && !x {print salts; x=1} 1' wp-config.php > wp-config.php.new
    mv wp-config.php.new wp-config.php

    # Set permissions
    print_info "Setting file permissions..."
    chown -R www-data:www-data "$WEB_ROOT"
    find "$WEB_ROOT" -type d -exec chmod 755 {} \;
    find "$WEB_ROOT" -type f -exec chmod 644 {} \;

    print_success "WordPress installed successfully!"
else
    print_step "6" "Skipping WordPress (already installed)"
fi

# --- STEP 7: Install Cloudflared ---
if [[ "$SKIP_CLOUDFLARED" != true ]] || ! command -v cloudflared >/dev/null 2>&1; then
    save_state "cloudflared_install"
    print_step "7" "Installing Cloudflared"

    cd /tmp

    # Get latest version
    CLOUDFLARED_VERSION=$(curl -s https://api.github.com/repos/cloudflare/cloudflared/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || echo "2024.10.0")
    print_info "Installing cloudflared $CLOUDFLARED_VERSION for $ARCH..."

    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-${ARCH}"

    wget --timeout=30 --tries=3 -O cloudflared "$CLOUDFLARED_URL" || error_exit "Failed to download cloudflared"

    chmod +x cloudflared
    mv cloudflared /usr/local/bin/

    if cloudflared --version >/dev/null 2>&1; then
        print_success "Cloudflared installed successfully!"
    else
        error_exit "Cloudflared installation verification failed"
    fi
else
    print_step "7" "Cloudflared already installed"
fi

# --- STEP 8: Authenticate with Cloudflare ---
save_state "cloudflare_auth"
print_step "8" "Authenticating with Cloudflare"

mkdir -p /root/.cloudflared

if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
    print_info "Starting Cloudflare authentication..."
    echo
    echo -e "${C_YELLOW}╔══════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_YELLOW}║  CLOUDFLARE AUTHENTICATION (HEADLESS MODE)                  ║${C_RESET}"
    echo -e "${C_YELLOW}╚══════════════════════════════════════════════════════════════╝${C_RESET}"
    echo
    echo -e "${C_CYAN}For headless/SSH installations:${C_RESET}"
    echo "  1. An authentication URL will be displayed below"
    echo "  2. Copy the ENTIRE URL"
    echo "  3. Open it in a browser on ANY device (phone, laptop, etc.)"
    echo "  4. Log in to your Cloudflare account"
    echo "  5. Select your domain and authorize"
    echo "  6. Return here and press Enter to continue"
    echo
    print_warning "IMPORTANT: Keep this terminal open while authenticating!"
    echo
    read -p "Press Enter when ready to see the authentication URL..."
    echo
    echo -e "${C_GREEN}Starting authentication...${C_RESET}"
    echo

    # Run cloudflared login and capture output to display URL
    # Use a temporary file to capture the output
    AUTH_OUTPUT=$(mktemp)

    # Run in background to capture output
    cloudflared tunnel login 2>&1 | tee "$AUTH_OUTPUT" &
    CLOUDFLARED_PID=$!

    # Wait a moment for the URL to be generated
    sleep 3

    # Extract and highlight the URL
    if grep -q "https://dash.cloudflare.com" "$AUTH_OUTPUT"; then
        AUTH_URL=$(grep -o "https://dash.cloudflare.com[^[:space:]]*" "$AUTH_OUTPUT" | head -1)
        echo
        echo -e "${C_GREEN}╔══════════════════════════════════════════════════════════════╗${C_RESET}"
        echo -e "${C_GREEN}║  COPY THIS URL AND OPEN IN YOUR BROWSER:                    ║${C_RESET}"
        echo -e "${C_GREEN}╚══════════════════════════════════════════════════════════════╝${C_RESET}"
        echo
        echo -e "${C_YELLOW}$AUTH_URL${C_RESET}"
        echo
        echo -e "${C_GREEN}══════════════════════════════════════════════════════════════${C_RESET}"
        echo
        print_info "Steps to complete authentication:"
        echo "  1. Copy the URL above"
        echo "  2. Open in browser (can be on any device)"
        echo "  3. Log in to Cloudflare"
        echo "  4. Select domain: $DOMAIN_NAME"
        echo "  5. Click 'Authorize'"
        echo
    fi

    # Wait for cloudflared process to complete
    wait $CLOUDFLARED_PID
    CLOUDFLARED_EXIT=$?
    rm -f "$AUTH_OUTPUT"

    if [ $CLOUDFLARED_EXIT -ne 0 ]; then
        error_exit "Cloudflare authentication failed. Please try again."
    fi

    if [[ ! -f /root/.cloudflared/cert.pem ]]; then
        error_exit "Authentication certificate not found. Please try: cloudflared tunnel login"
    fi

    echo
    print_success "Cloudflare authentication successful!"
else
    print_info "Using existing Cloudflare authentication."
fi

# --- STEP 9: Create/Configure Cloudflare Tunnel ---
save_state "tunnel_create"
print_step "9" "Configuring Cloudflare Tunnel"

# Check if tunnel already exists
TUNNEL_ID=$(cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}' | head -1)

if [[ -z "$TUNNEL_ID" ]]; then
    print_info "Creating new tunnel: $TUNNEL_NAME..."
    cloudflared tunnel create "$TUNNEL_NAME" || error_exit "Failed to create tunnel"

    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    [[ -z "$TUNNEL_ID" ]] && error_exit "Could not retrieve tunnel ID"

    print_success "Tunnel created: $TUNNEL_ID"
else
    print_info "Using existing tunnel: $TUNNEL_NAME ($TUNNEL_ID)"
fi

# Find credentials file
CREDENTIALS_FILE=$(find /root/.cloudflared -name "${TUNNEL_ID}.json" 2>/dev/null | head -n1)
[[ ! -f "$CREDENTIALS_FILE" ]] && error_exit "Tunnel credentials not found"

print_success "Credentials located: $CREDENTIALS_FILE"

# --- STEP 10: Configure Tunnel ---
save_state "tunnel_config"
print_step "10" "Creating Tunnel Configuration"

cat > /root/.cloudflared/config.yml <<CONFIG
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS_FILE

ingress:
  - hostname: $DOMAIN_NAME
    service: http://localhost:80
  - hostname: www.$DOMAIN_NAME
    service: http://localhost:80
  - service: http_status:404
CONFIG

print_success "Tunnel configuration created."

# --- STEP 11: Route DNS ---
save_state "dns_config"
print_step "11" "Configuring DNS"

print_info "Creating DNS entries..."
cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN_NAME" 2>/dev/null || print_warning "DNS for $DOMAIN_NAME may already exist"
cloudflared tunnel route dns "$TUNNEL_NAME" "www.$DOMAIN_NAME" 2>/dev/null || print_warning "DNS for www.$DOMAIN_NAME may already exist"

print_success "DNS configuration completed."

# --- STEP 12: Install Service ---
save_state "service_install"
print_step "12" "Installing Cloudflare Tunnel Service"

# Stop existing service if running
systemctl stop cloudflared 2>/dev/null || true

# Handle existing service installation
if systemctl list-unit-files | grep -q "cloudflared.service"; then
    print_info "Existing cloudflared service detected - uninstalling first..."
    cloudflared service uninstall 2>/dev/null || true
    sleep 2
fi

# Remove conflicting config in home directory
if [[ -f "/root/.cloudflared/config.yml" ]] && [[ -f "/etc/cloudflared/config.yml" ]]; then
    print_info "Removing conflicting config in /root/.cloudflared/"
    mv /root/.cloudflared/config.yml /root/.cloudflared/config.yml.backup 2>/dev/null || true
fi

# Move config to system location
mkdir -p /etc/cloudflared

# Copy config file
if [[ -f "/root/.cloudflared/config.yml" ]]; then
    cp /root/.cloudflared/config.yml /etc/cloudflared/config.yml
elif [[ ! -f "/etc/cloudflared/config.yml" ]]; then
    print_warning "Config file not found, this shouldn't happen!"
fi

# Copy credentials file
if [[ -f "$CREDENTIALS_FILE" ]]; then
    cp "$CREDENTIALS_FILE" /etc/cloudflared/
else
    error_exit "Credentials file not found: $CREDENTIALS_FILE"
fi

# Update config path to point to /etc/cloudflared
sed -i "s|/root/.cloudflared/|/etc/cloudflared/|g" /etc/cloudflared/config.yml

# Verify config file is valid
if [[ ! -f "/etc/cloudflared/config.yml" ]]; then
    error_exit "Config file missing in /etc/cloudflared/"
fi

print_info "Installing cloudflared service..."

# Install service with explicit config path
if cloudflared --config /etc/cloudflared/config.yml service install 2>&1 | tee -a "$LOG_FILE"; then
    print_success "Service installed successfully"
else
    print_warning "Service installation had issues, trying alternative method..."

    # Alternative: Create systemd service manually
    print_info "Creating systemd service manually..."

    cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=cloudflared
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared --config /etc/cloudflared/config.yml tunnel run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_success "Systemd service created manually"
fi

# Enable and start service
print_info "Enabling and starting cloudflared service..."

systemctl daemon-reload 2>/dev/null || true
systemctl enable cloudflared 2>&1 | tee -a "$LOG_FILE" || print_warning "Enable may have failed"
systemctl restart cloudflared 2>&1 | tee -a "$LOG_FILE" || print_warning "Restart may have failed"

sleep 5

# Check service status
if systemctl is-active --quiet cloudflared; then
    print_success "Cloudflare Tunnel service is running!"

    # Show tunnel info
    sleep 2
    if journalctl -u cloudflared -n 10 2>/dev/null | grep -qi "connection.*registered\|registered.*connection\|tunnel.*running"; then
        print_success "Tunnel is connected!"
    fi
else
    print_warning "Service may not be running correctly."
    echo
    print_info "Checking service status..."
    systemctl status cloudflared --no-pager -l | tail -20
    echo
    print_info "Checking tunnel logs..."
    journalctl -u cloudflared -n 20 --no-pager
    echo

    read -p "Service isn't running. Try to start manually? (y/N): " manual_start
    if [[ "$manual_start" =~ ^[Yy]$ ]]; then
        print_info "Attempting manual start..."
        systemctl start cloudflared
        sleep 3

        if systemctl is-active --quiet cloudflared; then
            print_success "Service started successfully!"
        else
            print_error "Could not start service. Manual intervention needed."
            print_info "Try: sudo cloudflared --config /etc/cloudflared/config.yml tunnel run"
        fi
    fi
fi

# --- STEP 13: Update WordPress URLs ---
save_state "wordpress_config"
print_step "13" "Configuring WordPress for Domain"

print_info "Updating WordPress site URLs in database..."

# Try to update WordPress URLs, but don't fail if wp_options doesn't exist yet
if mysql -u root -p"$MYSQL_ROOT_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'wp_options';" 2>/dev/null | grep -q "wp_options"; then
    print_info "Updating site URLs to https://$DOMAIN_NAME..."

    mysql -u root -p"$MYSQL_ROOT_PASS" "$DB_NAME" <<MYSQL_WP 2>/dev/null || print_warning "Could not update WordPress URLs (you can do this later)"
UPDATE wp_options SET option_value='https://$DOMAIN_NAME' WHERE option_name='siteurl';
UPDATE wp_options SET option_value='https://$DOMAIN_NAME' WHERE option_name='home';
MYSQL_WP

    print_success "WordPress configured for https://$DOMAIN_NAME"
else
    print_warning "WordPress tables not found - you'll need to complete WordPress installation first"
    print_info "After WordPress installation, visit: https://$DOMAIN_NAME"
fi

# --- STEP 14: Final Verification ---
save_state "verification"
print_step "14" "Verifying Installation"

echo
systemctl is-active --quiet apache2 && print_success "✓ Apache running" || print_error "✗ Apache not running"
systemctl is-active --quiet mariadb && print_success "✓ MariaDB running" || print_error "✗ MariaDB not running"
systemctl is-active --quiet cloudflared && print_success "✓ Cloudflare Tunnel running" || print_error "✗ Cloudflare Tunnel not running"
curl -s http://localhost >/dev/null 2>&1 && print_success "✓ Apache responding" || print_warning "⚠ Apache test failed"

# --- Installation Complete ---
save_state "completed"

SUMMARY_FILE="/root/cloudflare_tunnel_install_summary.txt"
cat > "$SUMMARY_FILE" <<SUMMARY
========================================
CLOUDFLARE TUNNEL INSTALLATION SUMMARY
========================================
Installation Date: $(date)
Domain: $DOMAIN_NAME
Local IP: $LOCAL_IP
Tunnel Name: $TUNNEL_NAME
Tunnel ID: $TUNNEL_ID

Website URLs:
  - https://$DOMAIN_NAME
  - https://www.$DOMAIN_NAME

WordPress Database:
  - Database: $DB_NAME
  - Username: $DB_USER
  - Password: $DB_PASS

MySQL Root Password: /root/.mysql_root_password

Important Files:
  - WordPress: /var/www/html
  - Tunnel Config: /etc/cloudflared/config.yml
  - Credentials: /etc/cloudflared/$(basename $CREDENTIALS_FILE)
  - Log File: $LOG_FILE
  - Backups: $BACKUP_DIR/

Service Commands:
  - systemctl status cloudflared
  - systemctl status apache2
  - systemctl status mariadb
  - journalctl -u cloudflared -f

========================================
SUMMARY

chmod 600 "$SUMMARY_FILE"

echo
echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${C_YELLOW}            🎉 INSTALLATION COMPLETE! 🎉                     ${C_RESET}"
echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo
print_success "Your WordPress website is now accessible from the internet!"
echo
echo -e "  🌐 Website:  ${C_GREEN}https://$DOMAIN_NAME${C_RESET}"
echo -e "  📋 Summary:  ${C_CYAN}$SUMMARY_FILE${C_RESET}"
echo -e "  📝 Log:      ${C_CYAN}$LOG_FILE${C_RESET}"
echo
print_info "Wait 2-5 minutes for DNS propagation, then visit your site!"
echo
print_warning "NEXT STEPS:"
echo "  1. Configure Cloudflare SSL: Dashboard → SSL/TLS → 'Full' mode"
echo "  2. Enable 'Always Use HTTPS'"
echo "  3. Visit https://$DOMAIN_NAME to complete WordPress setup"
echo "  4. Install security plugins and set up backups"
echo
print_success "Installation log saved to: $LOG_FILE"
echo

log "=== Installation completed successfully ==="
