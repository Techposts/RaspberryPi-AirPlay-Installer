#!/bin/bash

# ==============================================================================
# WordPress + Cloudflare Tunnel - Complete Automated Installer
# ==============================================================================
# This script installs and configures:
# - Apache2 Web Server
# - MariaDB Database
# - PHP 8.1+
# - WordPress (latest version)
# - Cloudflare Tunnel with automatic DNS configuration
# ==============================================================================

set -e  # Exit on any error

# Colors for output
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_MAGENTA='\033[0;35m'

# Logging functions
print_header() { echo -e "\n${C_MAGENTA}╔════════════════════════════════════════════════════════════╗${C_RESET}"; echo -e "${C_MAGENTA}║${C_RESET} ${C_CYAN}$1${C_RESET}"; echo -e "${C_MAGENTA}╚════════════════════════════════════════════════════════════╝${C_RESET}\n"; }
print_info() { echo -e "${C_BLUE}ℹ INFO:${C_RESET} $1"; }
print_success() { echo -e "${C_GREEN}✓ SUCCESS:${C_RESET} $1"; }
print_warning() { echo -e "${C_YELLOW}⚠ WARNING:${C_RESET} $1"; }
print_error() { echo -e "${C_RED}✗ ERROR:${C_RESET} $1"; }

# Log file
LOG_FILE="/var/log/wordpress-cloudflare-installer.log"
SUMMARY_FILE="/root/installation_summary.txt"
BACKUP_DIR="/root/installation_backups"

# Function to log and display
log_and_display() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Error handler
error_exit() {
    print_error "$1"
    echo "Check log file: $LOG_FILE"
    exit 1
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error_exit "This script must be run as root (use sudo)"
fi

clear
echo -e "${C_GREEN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_CYAN}   WordPress + Cloudflare Tunnel Installer${C_RESET}"
echo -e "${C_GREEN}════════════════════════════════════════════════════════════${C_RESET}"
echo
print_info "This script will install:"
echo "  • Apache2 Web Server"
echo "  • MariaDB Database"
echo "  • PHP 8.1+"
echo "  • WordPress (latest)"
echo "  • Cloudflare Tunnel"
echo
print_warning "This will take 5-10 minutes"
echo
read -p "Press ENTER to continue or CTRL+C to cancel..."

# Create backup directory
mkdir -p "$BACKUP_DIR"
mkdir -p /var/log

# Start logging
exec > >(tee -a "$LOG_FILE")
exec 2>&1

print_info "Installation started at $(date)"

# ==============================================================================
# STEP 1: Collect User Information
# ==============================================================================
print_header "STEP 1: Configuration"

# Get domain name
echo -e "${C_CYAN}Domain Configuration${C_RESET}"
echo "Examples: example.com, mysite.net, blog.io"
echo
while true; do
    read -p "Enter your domain name: " DOMAIN
    DOMAIN=$(echo "$DOMAIN" | xargs | tr '[:upper:]' '[:lower:]')  # Trim and lowercase
    
    if [[ -z "$DOMAIN" ]]; then
        print_error "Domain name cannot be empty"
        echo
        continue
    fi
    
    # Remove common prefixes if user included them
    DOMAIN="${DOMAIN#http://}"
    DOMAIN="${DOMAIN#https://}"
    DOMAIN="${DOMAIN#www.}"
    DOMAIN="${DOMAIN%/}"
    
    # Simple validation - must contain at least one dot and valid characters
    if [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$ ]]; then
        print_success "Domain accepted: $DOMAIN"
        echo
        break
    else
        print_error "Invalid domain format. Please enter a valid domain (e.g., example.com)"
        echo
    fi
done

# Get Cloudflare API Token
echo
print_info "You need a Cloudflare API Token with:"
echo "  • Zone:Zone:Edit permissions"
echo "  • Zone:DNS:Edit permissions"
echo "  Create one at: https://dash.cloudflare.com/profile/api-tokens"
echo
while true; do
    read -sp "Enter your Cloudflare API Token: " CF_API_TOKEN
    echo
    if [[ -z "$CF_API_TOKEN" ]]; then
        print_error "API Token cannot be empty"
        continue
    fi
    break
done

# Get Cloudflare Account ID
echo
print_info "Find your Account ID at: https://dash.cloudflare.com (right sidebar)"
while true; do
    read -p "Enter your Cloudflare Account ID: " CF_ACCOUNT_ID
    if [[ -z "$CF_ACCOUNT_ID" ]]; then
        print_error "Account ID cannot be empty"
        continue
    fi
    break
done

# Get Cloudflare Zone ID
echo
print_info "Find your Zone ID at: https://dash.cloudflare.com (Overview page, right sidebar)"
while true; do
    read -p "Enter your Cloudflare Zone ID for $DOMAIN: " CF_ZONE_ID
    if [[ -z "$CF_ZONE_ID" ]]; then
        print_error "Zone ID cannot be empty"
        continue
    fi
    break
done

# Generate secure passwords
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
WP_DB_PASSWORD=$(openssl rand -base64 24)
TUNNEL_SECRET=$(openssl rand -base64 32)

print_success "Configuration collected"

# ==============================================================================
# STEP 2: System Update
# ==============================================================================
print_header "STEP 2: Updating System"

print_info "Updating package lists..."
apt-get update -qq || error_exit "Failed to update package lists"

print_info "Upgrading existing packages..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

print_success "System updated"

# ==============================================================================
# STEP 3: Install Apache
# ==============================================================================
print_header "STEP 3: Installing Apache2"

print_info "Installing Apache2..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2 || error_exit "Failed to install Apache2"

print_info "Enabling Apache modules..."
a2enmod rewrite ssl headers expires || error_exit "Failed to enable Apache modules"

print_info "Starting Apache2..."
systemctl start apache2
systemctl enable apache2

if systemctl is-active --quiet apache2; then
    print_success "Apache2 installed and running"
else
    error_exit "Apache2 failed to start"
fi

# ==============================================================================
# STEP 4: Install MariaDB
# ==============================================================================
print_header "STEP 4: Installing MariaDB"

print_info "Installing MariaDB..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mariadb-server mariadb-client || error_exit "Failed to install MariaDB"

print_info "Starting MariaDB..."
systemctl start mariadb
systemctl enable mariadb

# Secure MariaDB installation
print_info "Securing MariaDB installation..."
mysql -e "UPDATE mysql.user SET Password=PASSWORD('$MYSQL_ROOT_PASSWORD') WHERE User='root';" 2>/dev/null || \
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -e "DROP DATABASE IF EXISTS test;"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -e "FLUSH PRIVILEGES;"

# Save MySQL root password
echo "$MYSQL_ROOT_PASSWORD" > /root/.mysql_root_password
chmod 600 /root/.mysql_root_password

if systemctl is-active --quiet mariadb; then
    print_success "MariaDB installed and secured"
else
    error_exit "MariaDB failed to start"
fi

# ==============================================================================
# STEP 5: Install PHP
# ==============================================================================
print_header "STEP 5: Installing PHP"

print_info "Installing PHP and extensions..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc \
    php-soap php-intl php-zip libapache2-mod-php || error_exit "Failed to install PHP"

# Configure PHP
print_info "Configuring PHP..."
PHP_INI=$(php -i | grep "Loaded Configuration File" | awk '{print $5}')
if [[ -f "$PHP_INI" ]]; then
    cp "$PHP_INI" "$BACKUP_DIR/php.ini.bak"
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
    sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI"
    sed -i 's/memory_limit = .*/memory_limit = 256M/' "$PHP_INI"
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
fi

systemctl restart apache2

print_success "PHP installed and configured"

# ==============================================================================
# STEP 6: Create WordPress Database
# ==============================================================================
print_header "STEP 6: Creating WordPress Database"

WP_DB_NAME="wordpress"
WP_DB_USER="wpuser"

print_info "Creating database and user..."
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
CREATE DATABASE IF NOT EXISTS $WP_DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$WP_DB_USER'@'localhost' IDENTIFIED BY '$WP_DB_PASSWORD';
GRANT ALL PRIVILEGES ON $WP_DB_NAME.* TO '$WP_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

print_success "WordPress database created"

# ==============================================================================
# STEP 7: Install WordPress
# ==============================================================================
print_header "STEP 7: Installing WordPress"

cd /tmp

print_info "Downloading WordPress..."
wget -q https://wordpress.org/latest.tar.gz || error_exit "Failed to download WordPress"

print_info "Extracting WordPress..."
tar -xzf latest.tar.gz

print_info "Moving WordPress files..."
rm -rf /var/www/html/*
cp -r wordpress/* /var/www/html/

print_info "Configuring WordPress..."
cd /var/www/html

# Create wp-config.php
cp wp-config-sample.php wp-config.php

# Generate WordPress salts
SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)

# Configure wp-config.php
sed -i "s/database_name_here/$WP_DB_NAME/" wp-config.php
sed -i "s/username_here/$WP_DB_USER/" wp-config.php
sed -i "s/password_here/$WP_DB_PASSWORD/" wp-config.php

# Replace salts
sed -i "/AUTH_KEY/,/NONCE_SALT/d" wp-config.php
sed -i "/define( 'DB_COLLATE', '' );/a\\$SALTS" wp-config.php

# Set correct permissions
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

# Create .htaccess for permalinks
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

# Cleanup
rm -f /tmp/latest.tar.gz
rm -rf /tmp/wordpress

print_success "WordPress installed"

# ==============================================================================
# STEP 8: Configure Apache for WordPress
# ==============================================================================
print_header "STEP 8: Configuring Apache"

print_info "Creating Apache virtual host..."
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

print_info "Enabling WordPress site..."
a2dissite 000-default.conf 2>/dev/null || true
a2ensite wordpress.conf

print_info "Testing Apache configuration..."
apache2ctl configtest || error_exit "Apache configuration test failed"

systemctl restart apache2

print_success "Apache configured for WordPress"

# ==============================================================================
# STEP 9: Install Cloudflared
# ==============================================================================
print_header "STEP 9: Installing Cloudflare Tunnel"

print_info "Adding Cloudflare GPG key..."
mkdir -p /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

print_info "Adding Cloudflare repository..."
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | \
    tee /etc/apt/sources.list.d/cloudflared.list

print_info "Installing cloudflared..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cloudflared || error_exit "Failed to install cloudflared"

print_success "Cloudflared installed"

# ==============================================================================
# STEP 10: Configure Cloudflare Tunnel
# ==============================================================================
print_header "STEP 10: Configuring Cloudflare Tunnel"

TUNNEL_NAME="wordpress-tunnel-$(date +%s)"

print_info "Authenticating with Cloudflare..."
mkdir -p /etc/cloudflared

# Create credentials file
cat > /root/.cloudflared/cert.json <<EOF
{
  "AccountTag": "$CF_ACCOUNT_ID",
  "TunnelSecret": "$TUNNEL_SECRET",
  "TunnelID": ""
}
EOF

print_info "Creating tunnel: $TUNNEL_NAME..."

# Create tunnel using API
TUNNEL_RESPONSE=$(curl -s -X POST \
    "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"name\":\"$TUNNEL_NAME\",\"tunnel_secret\":\"$TUNNEL_SECRET\"}")

TUNNEL_ID=$(echo "$TUNNEL_RESPONSE" | grep -o '"id":"[^"]*' | cut -d'"' -f4)

if [[ -z "$TUNNEL_ID" ]]; then
    print_error "Failed to create tunnel"
    echo "Response: $TUNNEL_RESPONSE"
    error_exit "Could not create Cloudflare tunnel"
fi

print_success "Tunnel created: $TUNNEL_ID"

# Create tunnel credentials file
mkdir -p /root/.cloudflared
cat > /root/.cloudflared/${TUNNEL_ID}.json <<EOF
{
  "AccountTag": "$CF_ACCOUNT_ID",
  "TunnelSecret": "$TUNNEL_SECRET",
  "TunnelID": "$TUNNEL_ID"
}
EOF

# Create tunnel configuration
cat > /etc/cloudflared/config.yml <<EOF
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/${TUNNEL_ID}.json

ingress:
  - hostname: $DOMAIN
    service: http://localhost:80
  - hostname: www.$DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF

print_info "Configuring DNS records..."

# Create DNS record for root domain
DNS_RESPONSE=$(curl -s -X POST \
    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"CNAME\",\"name\":\"@\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

if echo "$DNS_RESPONSE" | grep -q '"success":true'; then
    print_success "DNS record created for $DOMAIN"
else
    print_warning "Failed to create DNS record for root domain"
    echo "Response: $DNS_RESPONSE"
fi

# Create DNS record for www subdomain
DNS_RESPONSE_WWW=$(curl -s -X POST \
    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"CNAME\",\"name\":\"www\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

if echo "$DNS_RESPONSE_WWW" | grep -q '"success":true'; then
    print_success "DNS record created for www.$DOMAIN"
else
    print_warning "Failed to create DNS record for www subdomain"
fi

print_success "Cloudflare Tunnel configured"

# ==============================================================================
# STEP 11: Install and Start Tunnel Service
# ==============================================================================
print_header "STEP 11: Starting Cloudflare Tunnel Service"

print_info "Installing tunnel as a service..."
cloudflared service install

print_info "Starting tunnel service..."
systemctl start cloudflared
systemctl enable cloudflared

sleep 3

if systemctl is-active --quiet cloudflared; then
    print_success "Cloudflare Tunnel service is running"
else
    error_exit "Cloudflare Tunnel service failed to start"
fi

# ==============================================================================
# STEP 12: Create Installation Summary
# ==============================================================================
print_header "STEP 12: Creating Installation Summary"

cat > "$SUMMARY_FILE" <<EOF
════════════════════════════════════════════════════════════
WordPress + Cloudflare Tunnel Installation Summary
════════════════════════════════════════════════════════════
Installation Date: $(date)
Server Hostname: $(hostname)

WEBSITE INFORMATION
════════════════════════════════════════════════════════════
Website URL:        https://$DOMAIN
Alt URL (www):      https://www.$DOMAIN

CLOUDFLARE TUNNEL
════════════════════════════════════════════════════════════
Tunnel Name:        $TUNNEL_NAME
Tunnel ID:          $TUNNEL_ID
Account ID:         $CF_ACCOUNT_ID
Zone ID:            $CF_ZONE_ID

DATABASE CREDENTIALS
════════════════════════════════════════════════════════════
Database Name:      $WP_DB_NAME
Database User:      $WP_DB_USER
Database Password:  $WP_DB_PASSWORD
MySQL Root Pass:    (saved in /root/.mysql_root_password)

FILE LOCATIONS
════════════════════════════════════════════════════════════
WordPress:          /var/www/html/
Apache Config:      /etc/apache2/sites-available/wordpress.conf
Tunnel Config:      /etc/cloudflared/config.yml
Tunnel Credentials: /root/.cloudflared/${TUNNEL_ID}.json
MySQL Root Pass:    /root/.mysql_root_password
Installation Log:   $LOG_FILE
Backups:            $BACKUP_DIR

USEFUL COMMANDS
════════════════════════════════════════════════════════════
Check tunnel status:    sudo systemctl status cloudflared
View tunnel logs:       sudo journalctl -u cloudflared -f
Restart tunnel:         sudo systemctl restart cloudflared
Check Apache status:    sudo systemctl status apache2
Check MariaDB status:   sudo systemctl status mariadb
View Apache logs:       sudo tail -f /var/log/apache2/wordpress_error.log

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

print_success "Installation summary saved to $SUMMARY_FILE"

# ==============================================================================
# FINAL: Display Results
# ==============================================================================
clear
echo -e "${C_GREEN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_CYAN}           🎉 INSTALLATION COMPLETE! 🎉${C_RESET}"
echo -e "${C_GREEN}════════════════════════════════════════════════════════════${C_RESET}"
echo
echo -e "${C_YELLOW}📍 Service Status:${C_RESET}"
echo -n "  ✓ Apache2:      "
systemctl is-active --quiet apache2 && echo -e "${C_GREEN}RUNNING${C_RESET}" || echo -e "${C_RED}STOPPED${C_RESET}"
echo -n "  ✓ MariaDB:      "
systemctl is-active --quiet mariadb && echo -e "${C_GREEN}RUNNING${C_RESET}" || echo -e "${C_RED}STOPPED${C_RESET}"
echo -n "  ✓ Cloudflared:  "
systemctl is-active --quiet cloudflared && echo -e "${C_GREEN}RUNNING${C_RESET}" || echo -e "${C_RED}STOPPED${C_RESET}"
echo
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}🌐 YOUR WEBSITE${C_RESET}"
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "  URL:            ${C_GREEN}https://$DOMAIN${C_RESET}"
echo -e "  With www:       ${C_GREEN}https://www.$DOMAIN${C_RESET}"
echo
echo -e "${C_YELLOW}⚠️  WAIT 2-5 MINUTES FOR DNS PROPAGATION${C_RESET}"
echo
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}📋 NEXT STEPS${C_RESET}"
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo
echo "  1. Configure Cloudflare SSL:"
echo "     • Visit: https://dash.cloudflare.com"
echo "     • Select domain: $DOMAIN"
echo "     • SSL/TLS → Set to 'Full' or 'Flexible'"
echo "     • Enable 'Always Use HTTPS'"
echo
echo "  2. Complete WordPress Setup:"
echo "     • Visit: https://$DOMAIN"
echo "     • Follow the setup wizard"
echo "     • Create your admin account"
echo
echo "  3. Install Security Plugins:"
echo "     • Wordfence Security"
echo "     • UpdraftPlus Backup"
echo
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}📄 IMPORTANT FILES${C_RESET}"
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo "  Installation Summary:  $SUMMARY_FILE"
echo "  MySQL Root Password:   /root/.mysql_root_password"
echo "  Installation Log:      $LOG_FILE"
echo
echo -e "${C_GREEN}════════════════════════════════════════════════════════════${C_RESET}"
print_success "Installation completed successfully!"
echo -e "${C_GREEN}════════════════════════════════════════════════════════════${C_RESET}"
echo
print_info "View full details: cat $SUMMARY_FILE"
echo
