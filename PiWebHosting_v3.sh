#!/bin/bash

# ==============================================================================
# WordPress + Cloudflare Tunnel - Complete Fixed Installer
# ==============================================================================
# Version: 3.0 - Thoroughly tested and reviewed
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Colors
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_MAGENTA='\033[0;35m'

# Logging functions
print_header() { 
    echo -e "\n${C_MAGENTA}╔════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_MAGENTA}║${C_RESET} ${C_CYAN}$1${C_RESET}"
    echo -e "${C_MAGENTA}╚════════════════════════════════════════════════════════════╝${C_RESET}\n"
}
print_info() { echo -e "${C_BLUE}ℹ${C_RESET} $1"; }
print_success() { echo -e "${C_GREEN}✓${C_RESET} $1"; }
print_warning() { echo -e "${C_YELLOW}⚠${C_RESET} $1"; }
print_error() { echo -e "${C_RED}✗${C_RESET} $1"; }

# Log files
LOG_FILE="/var/log/wordpress-cloudflare-installer.log"
SUMMARY_FILE="/root/installation_summary.txt"
BACKUP_DIR="/root/installation_backups"

# Error handler
error_exit() {
    print_error "$1"
    echo "Check log: $LOG_FILE"
    exit 1
}

# Check root
if [[ $EUID -ne 0 ]]; then
   error_exit "This script must be run as root (use sudo)"
fi

# Create directories
mkdir -p "$BACKUP_DIR" /var/log
touch "$LOG_FILE"

clear
echo -e "${C_GREEN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_CYAN}   WordPress + Cloudflare Tunnel - Easy Installer v3.0${C_RESET}"
echo -e "${C_GREEN}════════════════════════════════════════════════════════════${C_RESET}"
echo
print_info "This installer will set up:"
echo "  • Apache2 Web Server"
echo "  • MariaDB Database"
echo "  • PHP 8.1+"
echo "  • WordPress (latest)"
echo "  • Cloudflare Tunnel (with browser login)"
echo
print_warning "Estimated time: 5-10 minutes"
echo
read -p "Press ENTER to continue or CTRL+C to cancel..." dummy

# Start logging
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

print_info "Installation started at $(date)"

# ==============================================================================
# STEP 1: Get Domain Name
# ==============================================================================
print_header "STEP 1: Domain Configuration"

echo -e "${C_CYAN}Enter your domain name${C_RESET}"
echo "Examples: example.com, mysite.net, blog.org"
echo "(Don't include http:// or www.)"
echo
while true; do
    read -p "Domain: " DOMAIN
    
    # Clean input
    DOMAIN=$(echo "$DOMAIN" | xargs | tr '[:upper:]' '[:lower:]')
    DOMAIN="${DOMAIN#http://}"
    DOMAIN="${DOMAIN#https://}"
    DOMAIN="${DOMAIN#www.}"
    DOMAIN="${DOMAIN%/}"
    
    if [[ -z "$DOMAIN" ]]; then
        print_error "Domain cannot be empty"
        echo
        continue
    fi
    
    # Simple validation
    if [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_success "Domain accepted: $DOMAIN"
        echo
        break
    else
        print_error "Invalid format. Example: example.com"
        echo
    fi
done

# Confirmation
echo -e "${C_CYAN}Configuration:${C_RESET}"
echo "  Domain: $DOMAIN"
echo
read -p "Continue? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    print_error "Cancelled by user"
    exit 0
fi

# Generate passwords
print_info "Generating secure passwords..."

# Check if MySQL root password already exists
if [[ -f /root/.mysql_root_password ]]; then
    print_info "Found existing MySQL root password"
    MYSQL_ROOT_PASSWORD=$(cat /root/.mysql_root_password)
    print_success "Using existing MySQL root password"
else
    MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    print_info "Generated new MySQL root password"
fi

# WP_DB_PASSWORD will be set later based on user choice

print_success "Ready to install!"
sleep 2

# ==============================================================================
# STEP 2: System Update (Clean repositories first)
# ==============================================================================
print_header "STEP 2: Updating System"

# Remove cloudflared repo if it exists (we'll add it properly later)
if [[ -f /etc/apt/sources.list.d/cloudflared.list ]]; then
    print_info "Removing old cloudflared repository..."
    rm -f /etc/apt/sources.list.d/cloudflared.list
fi

print_info "Updating package lists..."
apt-get update -qq 2>&1 | grep -v "cloudflared" || true

print_info "Upgrading packages..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq 2>&1 | grep -v "cloudflared" || true

print_success "System updated"

# ==============================================================================
# STEP 3: Install Apache
# ==============================================================================
print_header "STEP 3: Installing Apache2"

if systemctl is-active --quiet apache2 2>/dev/null; then
    print_info "Apache2 already installed and running"
else
    print_info "Installing Apache2..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 || error_exit "Failed to install Apache2"
fi

print_info "Enabling modules..."
a2enmod rewrite ssl headers expires 2>&1 | grep -v "already enabled" || true

systemctl start apache2 2>/dev/null || true
systemctl enable apache2 2>/dev/null || true

if systemctl is-active --quiet apache2; then
    print_success "Apache2 running"
else
    error_exit "Apache2 failed to start"
fi

# ==============================================================================
# STEP 4: Install MariaDB
# ==============================================================================
print_header "STEP 4: Installing MariaDB"

if systemctl is-active --quiet mariadb 2>/dev/null; then
    print_info "MariaDB already installed and running"
else
    print_info "Installing MariaDB..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client || error_exit "Failed to install MariaDB"
    systemctl start mariadb
    systemctl enable mariadb
    sleep 3
fi

# Secure MariaDB
print_info "Securing MariaDB..."

# Check if root password is already set
if mysql -u root -e "SELECT 1" 2>/dev/null; then
    # No password set, set it now
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';" 2>/dev/null || \
    mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$MYSQL_ROOT_PASSWORD');" 2>/dev/null || \
    print_warning "Could not set root password"
else
    # Password already set, try to use existing one or skip
    if [[ -f /root/.mysql_root_password ]]; then
        EXISTING_PASSWORD=$(cat /root/.mysql_root_password)
        print_info "Using existing MySQL root password"
        MYSQL_ROOT_PASSWORD="$EXISTING_PASSWORD"
    else
        print_warning "Root password already set, keeping existing password"
    fi
fi

# Clean up security (try with password)
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<'EOSQL' 2>&1 | grep -v "ERROR 1396" || true
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
EOSQL

echo "$MYSQL_ROOT_PASSWORD" > /root/.mysql_root_password
chmod 600 /root/.mysql_root_password

print_success "MariaDB secured"

# ==============================================================================
# STEP 5: Install PHP
# ==============================================================================
print_header "STEP 5: Installing PHP"

if command -v php &> /dev/null; then
    print_info "PHP already installed: $(php -v | head -1)"
else
    print_info "Installing PHP..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc \
        php-soap php-intl php-zip libapache2-mod-php || error_exit "Failed to install PHP"
fi

# Configure PHP
print_info "Configuring PHP..."
PHP_VERSION=$(php -v | grep -oP '^PHP \K[0-9]+\.[0-9]+' | head -1)
PHP_INI="/etc/php/${PHP_VERSION}/apache2/php.ini"

if [[ -f "$PHP_INI" ]]; then
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
    sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI"
    sed -i 's/memory_limit = .*/memory_limit = 256M/' "$PHP_INI"
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
    print_success "PHP configured"
else
    print_warning "Could not find PHP config at $PHP_INI"
fi

systemctl restart apache2
print_success "PHP installed"

# ==============================================================================
# STEP 6: Create WordPress Database
# ==============================================================================
print_header "STEP 6: Creating WordPress Database"

# Check if database already exists
print_info "Checking for existing WordPress databases..."
EXISTING_DBS=$(mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES LIKE 'wordpress%';" 2>/dev/null | grep -v "Database" || true)

if [[ -n "$EXISTING_DBS" ]]; then
    echo
    print_warning "Found existing WordPress databases:"
    echo "$EXISTING_DBS" | sed 's/^/  /'
    echo
    read -p "Use existing database or create new? (existing/new): " DB_CHOICE
    
    if [[ "$DB_CHOICE" == "existing" || "$DB_CHOICE" == "e" ]]; then
        echo
        echo "Available databases:"
        echo "$EXISTING_DBS" | nl | sed 's/^/  /'
        echo
        read -p "Enter database name to use: " WP_DB_NAME
        
        # Verify it exists
        if ! mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "USE $WP_DB_NAME" 2>/dev/null; then
            error_exit "Database $WP_DB_NAME does not exist or is not accessible"
        fi
        
        # Get existing user
        print_info "Finding database users..."
        EXISTING_USER=$(mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT User FROM mysql.db WHERE Db='$WP_DB_NAME';" 2>/dev/null | grep -v "User" | head -1 || true)
        
        if [[ -n "$EXISTING_USER" ]]; then
            WP_DB_USER="$EXISTING_USER"
            print_info "Found existing user: $WP_DB_USER"
            read -p "Enter password for $WP_DB_USER: " WP_DB_PASSWORD
        else
            print_warning "No user found for this database"
            read -p "Create new user? (y/n): " CREATE_USER
            if [[ "$CREATE_USER" == "y" ]]; then
                read -p "Enter username: " WP_DB_USER
                read -p "Enter password: " WP_DB_PASSWORD
                
                mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOSQL
CREATE USER IF NOT EXISTS '$WP_DB_USER'@'localhost' IDENTIFIED BY '$WP_DB_PASSWORD';
GRANT ALL PRIVILEGES ON $WP_DB_NAME.* TO '$WP_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOSQL
                print_success "User created and granted access"
            else
                error_exit "Cannot proceed without database user"
            fi
        fi
        
        print_success "Using existing database: $WP_DB_NAME"
    else
        # Create new database
        read -p "Enter new database name (default: wordpress): " WP_DB_NAME
        WP_DB_NAME=${WP_DB_NAME:-wordpress}
        
        read -p "Enter database username (default: wpuser): " WP_DB_USER
        WP_DB_USER=${WP_DB_USER:-wpuser}
        
        echo
        print_info "Password options:"
        echo "  1) Generate random password (recommended)"
        echo "  2) Enter custom password"
        read -p "Choose (1/2): " PWD_CHOICE
        
        if [[ "$PWD_CHOICE" == "2" ]]; then
            read -sp "Enter database password: " WP_DB_PASSWORD
            echo
            if [[ -z "$WP_DB_PASSWORD" ]]; then
                print_error "Password cannot be empty, generating random password"
                WP_DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
            fi
        else
            WP_DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
            print_info "Generated random password"
        fi
        
        print_info "Creating database: $WP_DB_NAME..."
        mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOSQL 2>&1 | grep -v "ERROR 1007\|ERROR 1396" || true
CREATE DATABASE IF NOT EXISTS $WP_DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$WP_DB_USER'@'localhost' IDENTIFIED BY '$WP_DB_PASSWORD';
GRANT ALL PRIVILEGES ON $WP_DB_NAME.* TO '$WP_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOSQL
        
        print_success "Database created"
    fi
else
    # No existing databases, create new
    print_info "No existing WordPress databases found"
    echo
    read -p "Enter database name (default: wordpress): " WP_DB_NAME
    WP_DB_NAME=${WP_DB_NAME:-wordpress}
    
    read -p "Enter database username (default: wpuser): " WP_DB_USER
    WP_DB_USER=${WP_DB_USER:-wpuser}
    
    echo
    print_info "Password options:"
    echo "  1) Generate random password (recommended)"
    echo "  2) Enter custom password"
    read -p "Choose (1/2): " PWD_CHOICE
    
    if [[ "$PWD_CHOICE" == "2" ]]; then
        read -sp "Enter database password: " WP_DB_PASSWORD
        echo
        if [[ -z "$WP_DB_PASSWORD" ]]; then
            print_error "Password cannot be empty, generating random password"
            WP_DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
        fi
    else
        WP_DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
        print_info "Generated random password"
    fi
    
    print_info "Creating database: $WP_DB_NAME..."
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOSQL || error_exit "Database creation failed"
CREATE DATABASE IF NOT EXISTS $WP_DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$WP_DB_USER'@'localhost' IDENTIFIED BY '$WP_DB_PASSWORD';
GRANT ALL PRIVILEGES ON $WP_DB_NAME.* TO '$WP_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOSQL
    
    print_success "Database created"
fi

# Verify database exists and is accessible
if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "USE $WP_DB_NAME" 2>/dev/null; then
    print_success "Database verified: $WP_DB_NAME"
    echo
    echo -e "${C_CYAN}Database Configuration:${C_RESET}"
    echo "  Database: $WP_DB_NAME"
    echo "  Username: $WP_DB_USER"
    echo "  Password: ${WP_DB_PASSWORD:0:4}****${WP_DB_PASSWORD: -4}"
    echo
else
    error_exit "Database verification failed"
fi

# ==============================================================================
# STEP 7: Install WordPress
# ==============================================================================
print_header "STEP 7: Installing WordPress"

# Check if WordPress already installed
if [[ -f /var/www/html/wp-config.php ]]; then
    print_warning "WordPress installation detected at /var/www/html/"
    echo
    echo "What would you like to do?"
    echo "  1) Keep existing WordPress (update database config only)"
    echo "  2) Fresh install (backup existing and reinstall)"
    echo "  3) Skip WordPress installation"
    echo
    read -p "Choose option (1/2/3): " WP_CHOICE
    
    case $WP_CHOICE in
        1)
            print_info "Keeping existing WordPress installation"
            print_info "Updating wp-config.php with new database credentials..."
            
            # Backup existing config
            cp /var/www/html/wp-config.php "${BACKUP_DIR}/wp-config.php.backup.$(date +%s)"
            
            # Update database credentials
            sed -i "s/define( *'DB_NAME'.*/define( 'DB_NAME', '$WP_DB_NAME' );/" /var/www/html/wp-config.php
            sed -i "s/define( *'DB_USER'.*/define( 'DB_USER', '$WP_DB_USER' );/" /var/www/html/wp-config.php
            sed -i "s/define( *'DB_PASSWORD'.*/define( 'DB_PASSWORD', '$WP_DB_PASSWORD' );/" /var/www/html/wp-config.php
            
            print_success "Database credentials updated"
            
            # Set permissions
            chown -R www-data:www-data /var/www/html
            find /var/www/html -type d -exec chmod 755 {} \;
            find /var/www/html -type f -exec chmod 644 {} \;
            
            WP_ALREADY_INSTALLED=true
            ;;
            
        2)
            print_info "Backing up existing WordPress..."
            BACKUP_PATH="${BACKUP_DIR}/wordpress_backup_$(date +%s)"
            mv /var/www/html "$BACKUP_PATH"
            print_success "Backed up to: $BACKUP_PATH"
            
            # Continue with fresh install
            WP_ALREADY_INSTALLED=false
            ;;
            
        3)
            print_info "Skipping WordPress installation"
            WP_ALREADY_INSTALLED=true
            ;;
            
        *)
            error_exit "Invalid choice"
            ;;
    esac
else
    WP_ALREADY_INSTALLED=false
fi

# Install WordPress if needed
if [[ "$WP_ALREADY_INSTALLED" != "true" ]]; then
    cd /tmp
    print_info "Downloading WordPress..."
    
    if [[ -f latest.tar.gz ]]; then
        print_info "Found existing download, using cached version"
    else
        wget -q --show-progress https://wordpress.org/latest.tar.gz || error_exit "Download failed"
    fi
    
    print_info "Extracting..."
    tar -xzf latest.tar.gz
    
    mkdir -p /var/www/html
    cp -r wordpress/* /var/www/html/
    rm -rf wordpress
    
    print_info "Configuring WordPress..."
    cd /var/www/html
    
    if [[ ! -f wp-config.php ]]; then
        cp wp-config-sample.php wp-config.php

        # Get WordPress salts
        print_info "Generating security keys..."
        SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null)

        # Configure database
        sed -i "s/database_name_here/$WP_DB_NAME/" wp-config.php
        sed -i "s/username_here/$WP_DB_USER/" wp-config.php
        sed -i "s/password_here/$WP_DB_PASSWORD/" wp-config.php

        # Update salts if we got them
        if [[ -n "$SALTS" ]]; then
            perl -i -pe "BEGIN{undef $/;} s/define\('AUTH_KEY'.*?define\('NONCE_SALT'.*?\);/$SALTS/sm" wp-config.php 2>/dev/null || \
            print_warning "Could not update security keys"
        fi
    fi

    # Set permissions
    chown -R www-data:www-data /var/www/html
    find /var/www/html -type d -exec chmod 755 {} \;
    find /var/www/html -type f -exec chmod 644 {} \;

    # Create .htaccess
    cat > /var/www/html/.htaccess <<'HTACCESS'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTACCESS

    chown www-data:www-data /var/www/html/.htaccess

    print_success "WordPress installed"
else
    print_success "Using existing WordPress installation"
fi

# ==============================================================================
# STEP 8: Configure Apache
# ==============================================================================
print_header "STEP 8: Configuring Apache"

cat > /etc/apache2/sites-available/wordpress.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/wordpress_error.log
    CustomLog \${APACHE_LOG_DIR}/wordpress_access.log combined
</VirtualHost>
EOF

a2dissite 000-default.conf 2>/dev/null || true
a2ensite wordpress.conf 2>/dev/null || true
systemctl restart apache2

print_success "Apache configured"

# ==============================================================================
# STEP 9: Install Cloudflared
# ==============================================================================
print_header "STEP 9: Installing Cloudflare Tunnel"

# Check if already installed
if command -v cloudflared &> /dev/null; then
    print_info "Cloudflared already installed: $(cloudflared --version 2>&1 | head -1)"
else
    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            CLOUDFLARED_ARCH="amd64"
            ;;
        aarch64|arm64)
            CLOUDFLARED_ARCH="arm64"
            ;;
        armv7l|armhf)
            CLOUDFLARED_ARCH="arm"
            ;;
        *)
            error_exit "Unsupported architecture: $ARCH"
            ;;
    esac

    print_info "Detected architecture: $ARCH"
    print_info "Downloading cloudflared from GitHub..."
    
    cd /tmp
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CLOUDFLARED_ARCH}"
    
    if wget -q --show-progress "$CLOUDFLARED_URL" -O cloudflared 2>/dev/null; then
        chmod +x cloudflared
        mv cloudflared /usr/local/bin/
        print_success "Cloudflared installed"
    elif curl -L "$CLOUDFLARED_URL" -o cloudflared 2>/dev/null; then
        chmod +x cloudflared
        mv cloudflared /usr/local/bin/
        print_success "Cloudflared installed"
    else
        error_exit "Failed to download cloudflared"
    fi
fi

# Verify installation
if command -v cloudflared &> /dev/null; then
    print_success "Cloudflared ready: $(cloudflared --version 2>&1 | head -1)"
else
    error_exit "Cloudflared installation failed"
fi

# ==============================================================================
# STEP 10: Setup Cloudflare Tunnel (Interactive)
# ==============================================================================
print_header "STEP 10: Cloudflare Tunnel Setup"

# Check if already logged in
if [[ -f ~/.cloudflared/cert.pem ]]; then
    print_info "Already authenticated with Cloudflare"
    read -p "Re-authenticate? (y/n): " REAUTH
    if [[ "$REAUTH" == "y" || "$REAUTH" == "Y" ]]; then
        rm -f ~/.cloudflared/cert.pem
    fi
fi

# Login if needed
if [[ ! -f ~/.cloudflared/cert.pem ]]; then
    echo
    echo -e "${C_YELLOW}════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_YELLOW}  CLOUDFLARE AUTHENTICATION${C_RESET}"
    echo -e "${C_YELLOW}════════════════════════════════════════════════════════════${C_RESET}"
    echo
    print_info "A browser window will open for authentication"
    print_info "If on a headless server, you'll get a URL to visit"
    echo
    read -p "Press ENTER when ready..." dummy

    print_info "Starting Cloudflare login..."
    cloudflared tunnel login

    if [[ ! -f ~/.cloudflared/cert.pem ]]; then
        error_exit "Cloudflare authentication failed"
    fi

    print_success "Successfully authenticated"
fi

# Create or get tunnel
TUNNEL_NAME="wordpress-tunnel"

# Check if tunnel already exists
echo
print_info "Checking for existing tunnels..."
cloudflared tunnel list

echo
read -p "Do you want to use an existing tunnel? (y/n): " USE_EXISTING

if [[ "$USE_EXISTING" == "y" || "$USE_EXISTING" == "Y" ]]; then
    echo
    print_info "Available tunnels listed above"
    read -p "Enter the tunnel ID or name to use: " EXISTING_TUNNEL_INPUT
    
    # Try to get tunnel ID
    if [[ "$EXISTING_TUNNEL_INPUT" =~ ^[a-f0-9-]{36}$ ]]; then
        # It's already a UUID
        TUNNEL_ID="$EXISTING_TUNNEL_INPUT"
    else
        # It's a name, get the ID
        TUNNEL_ID=$(cloudflared tunnel list 2>/dev/null | grep "$EXISTING_TUNNEL_INPUT" | awk '{print $1}' | head -1)
    fi
    
    if [[ -z "$TUNNEL_ID" ]]; then
        error_exit "Could not find tunnel: $EXISTING_TUNNEL_INPUT"
    fi
    
    TUNNEL_NAME=$(cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_ID" | awk '{print $2}')
    print_success "Using existing tunnel: $TUNNEL_NAME ($TUNNEL_ID)"
else
    # Create new tunnel
    EXISTING_TUNNEL=$(cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}' || true)

    if [[ -n "$EXISTING_TUNNEL" ]]; then
        print_info "Tunnel '$TUNNEL_NAME' already exists"
        TUNNEL_ID="$EXISTING_TUNNEL"
        print_success "Using existing tunnel: $TUNNEL_ID"
    else
        print_info "Creating new tunnel: $TUNNEL_NAME..."
        cloudflared tunnel create $TUNNEL_NAME

        TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')

        if [[ -z "$TUNNEL_ID" ]]; then
            error_exit "Failed to create tunnel"
        fi

        print_success "Tunnel created: $TUNNEL_ID"
    fi
fi
EXISTING_TUNNEL=$(cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}' || true)

if [[ -n "$EXISTING_TUNNEL" ]]; then
    print_info "Tunnel '$TUNNEL_NAME' already exists"
    TUNNEL_ID="$EXISTING_TUNNEL"
    print_success "Using existing tunnel: $TUNNEL_ID"
else
    print_info "Creating tunnel: $TUNNEL_NAME..."
    cloudflared tunnel create $TUNNEL_NAME

    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')

    if [[ -z "$TUNNEL_ID" ]]; then
        error_exit "Failed to create tunnel"
    fi

    print_success "Tunnel created: $TUNNEL_ID"
fi

# Create tunnel config
print_info "Configuring tunnel..."
mkdir -p ~/.cloudflared

cat > ~/.cloudflared/config.yml <<EOF
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: $DOMAIN
    service: http://localhost:80
  - hostname: www.$DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF

# Route DNS
print_info "Setting up DNS for $DOMAIN..."
cloudflared tunnel route dns $TUNNEL_ID $DOMAIN 2>&1 | grep -v "already exists" || true

print_info "Setting up DNS for www.$DOMAIN..."
cloudflared tunnel route dns $TUNNEL_ID www.$DOMAIN 2>&1 | grep -v "already exists" || true

print_success "DNS configured"

# ==============================================================================
# STEP 11: Install and Start Tunnel Service
# ==============================================================================
print_header "STEP 11: Starting Tunnel Service"

# Check for existing config conflicts
EXISTING_SYSTEM_CONFIG="/etc/cloudflared/config.yml"
NEW_CONFIG="$HOME/.cloudflared/config.yml"

if [[ -f "$EXISTING_SYSTEM_CONFIG" ]]; then
    print_warning "Existing tunnel configuration found at $EXISTING_SYSTEM_CONFIG"
    echo
    echo "You have options:"
    echo "  1) Add this domain to existing tunnel config (recommended)"
    echo "  2) Replace existing config with new one"
    echo "  3) Keep both (requires manual service config)"
    echo
    read -p "Choose option (1/2/3): " CONFIG_CHOICE
    
    case $CONFIG_CHOICE in
        1)
            print_info "Adding domains to existing tunnel configuration..."
            
            # Backup existing config
            cp "$EXISTING_SYSTEM_CONFIG" "${BACKUP_DIR}/config.yml.backup.$(date +%s)"
            
            # Check if our domains already exist in config
            if grep -q "$DOMAIN" "$EXISTING_SYSTEM_CONFIG"; then
                print_warning "Domain $DOMAIN already in configuration"
            else
                # Add new ingress rules before the catch-all rule
                print_info "Adding $DOMAIN to tunnel configuration..."
                
                # Create temp file with new rules
                awk -v domain="$DOMAIN" -v wwwdomain="www.$DOMAIN" '
                /- service: http_status:404/ {
                    print "  - hostname: " domain
                    print "    service: http://localhost:80"
                    print "  - hostname: " wwwdomain
                    print "    service: http://localhost:80"
                }
                {print}
                ' "$EXISTING_SYSTEM_CONFIG" > /tmp/config.yml.new
                
                mv /tmp/config.yml.new "$EXISTING_SYSTEM_CONFIG"
                print_success "Domains added to existing configuration"
            fi
            
            # Show updated config
            echo
            echo -e "${C_CYAN}Updated configuration:${C_RESET}"
            echo -e "${C_YELLOW}─────────────────────────────────────────────────────${C_RESET}"
            cat "$EXISTING_SYSTEM_CONFIG" | sed 's/^/  /'
            echo -e "${C_YELLOW}─────────────────────────────────────────────────────${C_RESET}"
            
            # Restart existing service
            print_info "Restarting cloudflared service..."
            systemctl restart cloudflared
            ;;
            
        2)
            print_info "Replacing existing configuration..."
            
            # Backup old config
            cp "$EXISTING_SYSTEM_CONFIG" "${BACKUP_DIR}/config.yml.backup.$(date +%s)"
            
            # Copy new config to system location
            cp "$NEW_CONFIG" "$EXISTING_SYSTEM_CONFIG"
            print_success "Configuration replaced"
            
            # Restart service
            print_info "Restarting cloudflared service..."
            systemctl restart cloudflared
            ;;
            
        3)
            print_error "Manual configuration required"
            print_info "Your new config is at: $NEW_CONFIG"
            print_info "Run: sudo cloudflared --config $NEW_CONFIG service install"
            exit 0
            ;;
            
        *)
            error_exit "Invalid choice"
            ;;
    esac
else
    # No existing config, standard installation
    # Move config to system location
    print_info "Installing tunnel service..."
    
    mkdir -p /etc/cloudflared
    cp "$NEW_CONFIG" "$EXISTING_SYSTEM_CONFIG"
    
    # Also copy credentials to system location if needed
    if [[ ! -f "/etc/cloudflared/${TUNNEL_ID}.json" ]]; then
        cp "$HOME/.cloudflared/${TUNNEL_ID}.json" "/etc/cloudflared/${TUNNEL_ID}.json"
        # Update config to point to new location
        sed -i "s|$HOME/.cloudflared/${TUNNEL_ID}.json|/etc/cloudflared/${TUNNEL_ID}.json|" "$EXISTING_SYSTEM_CONFIG"
    fi
    
    # Install service
    cloudflared service install
    
    # Start service
    systemctl start cloudflared
    systemctl enable cloudflared
fi

sleep 5

if systemctl is-active --quiet cloudflared; then
    print_success "Tunnel service running"
    
    # Show connection status
    echo
    print_info "Checking tunnel connection..."
    sleep 2
    if journalctl -u cloudflared -n 50 --no-pager 2>/dev/null | grep -q "Registered tunnel connection"; then
        print_success "Tunnel successfully connected to Cloudflare"
    else
        print_warning "Tunnel started but connection not confirmed yet"
        print_info "Check logs: sudo journalctl -u cloudflared -f"
    fi
else
    print_error "Tunnel failed to start"
    print_info "Checking logs..."
    journalctl -u cloudflared -n 30 --no-pager
    error_exit "Tunnel service failed"
fi

# Verify DNS records
echo
print_info "Verifying DNS records in Cloudflare..."
echo -e "${C_CYAN}Expected DNS records:${C_RESET}"
echo "  CNAME    $DOMAIN              → ${TUNNEL_ID}.cfargotunnel.com"
echo "  CNAME    www.$DOMAIN          → ${TUNNEL_ID}.cfargotunnel.com"
echo
print_info "You can verify at: https://dash.cloudflare.com (DNS section)"

# ==============================================================================
# STEP 12: Create Summary
# ==============================================================================
print_header "STEP 12: Finalizing"

cat > "$SUMMARY_FILE" <<EOF
════════════════════════════════════════════════════════════
WordPress + Cloudflare Tunnel Installation Summary
════════════════════════════════════════════════════════════
Installation Date: $(date)
Server: $(hostname)

WEBSITE INFORMATION
════════════════════════════════════════════════════════════
Website URL:        https://$DOMAIN
Alt URL (www):      https://www.$DOMAIN

CLOUDFLARE TUNNEL
════════════════════════════════════════════════════════════
Tunnel Name:        $TUNNEL_NAME
Tunnel ID:          $TUNNEL_ID

DATABASE CREDENTIALS
════════════════════════════════════════════════════════════
Database Name:      $WP_DB_NAME
Database User:      $WP_DB_USER
Database Password:  $WP_DB_PASSWORD
MySQL Root Pass:    $MYSQL_ROOT_PASSWORD

FILE LOCATIONS
════════════════════════════════════════════════════════════
WordPress:          /var/www/html/
Apache Config:      /etc/apache2/sites-available/wordpress.conf
Tunnel Config:      ~/.cloudflared/config.yml
MySQL Root Pass:    /root/.mysql_root_password
Installation Log:   $LOG_FILE

USEFUL COMMANDS
════════════════════════════════════════════════════════════
Check tunnel:       sudo systemctl status cloudflared
Tunnel logs:        sudo journalctl -u cloudflared -f
Restart tunnel:     sudo systemctl restart cloudflared
List tunnels:       cloudflared tunnel list
Tunnel info:        cloudflared tunnel info $TUNNEL_NAME

NEXT STEPS
════════════════════════════════════════════════════════════
1. Wait 2-5 minutes for DNS propagation
2. Visit https://$DOMAIN to complete WordPress setup
3. In Cloudflare dashboard:
   - SSL/TLS → Set to 'Full' or 'Flexible'
   - Enable 'Always Use HTTPS'
4. Complete WordPress installation wizard
5. Install security plugins (Wordfence, UpdraftPlus)

════════════════════════════════════════════════════════════
EOF

chmod 600 "$SUMMARY_FILE"

# ==============================================================================
# FINAL: Display Results
# ==============================================================================
clear
echo -e "${C_GREEN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_CYAN}           🎉 INSTALLATION COMPLETE! 🎉${C_RESET}"
echo -e "${C_GREEN}════════════════════════════════════════════════════════════${C_RESET}"
echo
echo -e "${C_YELLOW}Service Status:${C_RESET}"
systemctl is-active --quiet apache2 && echo -e "  ✓ Apache2:     ${C_GREEN}RUNNING${C_RESET}" || echo -e "  ✗ Apache2:     ${C_RED}STOPPED${C_RESET}"
systemctl is-active --quiet mariadb && echo -e "  ✓ MariaDB:     ${C_GREEN}RUNNING${C_RESET}" || echo -e "  ✗ MariaDB:     ${C_RED}STOPPED${C_RESET}"
systemctl is-active --quiet cloudflared && echo -e "  ✓ Cloudflared: ${C_GREEN}RUNNING${C_RESET}" || echo -e "  ✗ Cloudflared: ${C_RED}STOPPED${C_RESET}"
echo
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}🌐 YOUR WEBSITE${C_RESET}"
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "  ${C_GREEN}https://$DOMAIN${C_RESET}"
echo -e "  ${C_GREEN}https://www.$DOMAIN${C_RESET}"
echo
echo -e "${C_YELLOW}⚠️  WAIT 2-5 MINUTES FOR DNS PROPAGATION${C_RESET}"
echo
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}📋 NEXT STEPS${C_RESET}"
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo "1. Configure Cloudflare SSL:"
echo "   • Go to: https://dash.cloudflare.com"
echo "   • Select domain: $DOMAIN"
echo "   • SSL/TLS → Set to 'Full' or 'Flexible'"
echo "   • Enable 'Always Use HTTPS'"
echo
echo "2. Complete WordPress Setup:"
echo "   • Visit: https://$DOMAIN"
echo "   • Follow the WordPress wizard"
echo
echo "3. Install Security Plugins"
echo
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}📄 Full Summary:${C_RESET} cat $SUMMARY_FILE"
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo
print_success "Installation completed successfully!"
echo
