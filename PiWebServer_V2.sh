#!/bin/bash

# ==============================================================================
# WordPress + Cloudflare Tunnel - Complete Automated Installer (Fixed)
# ==============================================================================
# Version: 2.0
# This script installs and configures:
# - Apache2, MariaDB, PHP, WordPress, Cloudflare Tunnel
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Colors for output
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

# Log file
LOG_FILE="/var/log/wordpress-cloudflare-installer.log"
SUMMARY_FILE="/root/installation_summary.txt"
BACKUP_DIR="/root/installation_backups"

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

# Create necessary directories
mkdir -p "$BACKUP_DIR"
mkdir -p /var/log
touch "$LOG_FILE"

clear
echo -e "${C_GREEN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_CYAN}   WordPress + Cloudflare Tunnel Installer v2.0${C_RESET}"
echo -e "${C_GREEN}════════════════════════════════════════════════════════════${C_RESET}"
echo
print_info "This script will install:"
echo "  • Apache2 Web Server"
echo "  • MariaDB Database"
echo "  • PHP 8.1+"
echo "  • WordPress (latest)"
echo "  • Cloudflare Tunnel with DNS"
echo
print_warning "This will take 5-10 minutes"
echo
read -p "Press ENTER to continue or CTRL+C to cancel..." dummy

# Start logging
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

print_info "Installation started at $(date)"

# ==============================================================================
# STEP 1: Collect User Information
# ==============================================================================
print_header "STEP 1: Configuration"

# Get domain name
echo -e "${C_CYAN}Domain Configuration${C_RESET}"
echo "Enter your domain name (without http:// or www.)"
echo "Examples: example.com, mysite.net, blog.org"
echo
while true; do
    read -p "Domain: " DOMAIN
    
    # Clean input
    DOMAIN=$(echo "$DOMAIN" | xargs)
    DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]')
    DOMAIN="${DOMAIN#http://}"
    DOMAIN="${DOMAIN#https://}"
    DOMAIN="${DOMAIN#www.}"
    DOMAIN="${DOMAIN%/}"
    
    if [[ -z "$DOMAIN" ]]; then
        print_error "Domain cannot be empty. Please try again."
        echo
        continue
    fi
    
    # Simple but effective validation
    if [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_success "Domain accepted: $DOMAIN"
        echo
        break
    else
        print_error "Invalid domain format. Please enter a valid domain like 'example.com'"
        echo
    fi
done

# Get Cloudflare API Token
echo -e "${C_CYAN}Cloudflare API Token${C_RESET}"
echo "Create a token at: https://dash.cloudflare.com/profile/api-tokens"
echo "Click 'Create Token' → Use 'Edit zone DNS' template"
echo
while true; do
    read -sp "Enter API Token (hidden): " CF_API_TOKEN
    echo
    
    CF_API_TOKEN=$(echo "$CF_API_TOKEN" | xargs)
    
    if [[ -z "$CF_API_TOKEN" ]]; then
        print_error "Token cannot be empty"
        echo
        continue
    fi
    
    if [[ ${#CF_API_TOKEN} -lt 20 ]]; then
        print_error "Token seems too short (should be 40+ characters)"
        echo
        continue
    fi
    
    print_info "Verifying token..."
    TOKEN_TEST=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    if echo "$TOKEN_TEST" | grep -q '"status":"active"'; then
        print_success "Token verified successfully"
        echo
        break
    else
        print_error "Token verification failed. Please check and try again."
        ERROR_MSG=$(echo "$TOKEN_TEST" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
        if [[ -n "$ERROR_MSG" ]]; then
            echo "  Error: $ERROR_MSG"
        fi
        echo
        read -p "Try again? (y/n): " retry
        if [[ "$retry" != "y" && "$retry" != "Y" ]]; then
            exit 0
        fi
    fi
done

# Get Cloudflare Account ID
echo -e "${C_CYAN}Cloudflare Account ID${C_RESET}"
echo "Find it at: https://dash.cloudflare.com"
echo "(Look in the right sidebar on any page)"
echo
while true; do
    read -p "Account ID: " CF_ACCOUNT_ID
    
    CF_ACCOUNT_ID=$(echo "$CF_ACCOUNT_ID" | xargs)
    
    if [[ -z "$CF_ACCOUNT_ID" ]]; then
        print_error "Account ID cannot be empty"
        echo
        continue
    fi
    
    if [[ ${#CF_ACCOUNT_ID} -ne 32 ]] || [[ ! "$CF_ACCOUNT_ID" =~ ^[a-f0-9]+$ ]]; then
        print_warning "Format looks unusual (expected 32 hex characters)"
        read -p "Continue anyway? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo
            continue
        fi
    fi
    
    print_success "Account ID accepted"
    echo
    break
done

# Get or auto-detect Zone ID
echo -e "${C_CYAN}Cloudflare Zone ID${C_RESET}"
echo "We can try to auto-detect your Zone ID"
echo
read -p "Auto-detect Zone ID? (y/n): " AUTO_ZONE

if [[ "$AUTO_ZONE" == "y" || "$AUTO_ZONE" == "Y" ]]; then
    print_info "Searching for zone: $DOMAIN..."
    
    ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    CF_ZONE_ID=$(echo "$ZONE_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    
    if [[ -n "$CF_ZONE_ID" && ${#CF_ZONE_ID} -eq 32 ]]; then
        print_success "Found Zone ID: $CF_ZONE_ID"
        echo
    else
        print_warning "Auto-detection failed. Please enter manually."
        echo "Find it at: https://dash.cloudflare.com/$DOMAIN (right sidebar)"
        echo
        while true; do
            read -p "Zone ID: " CF_ZONE_ID
            CF_ZONE_ID=$(echo "$CF_ZONE_ID" | xargs)
            
            if [[ -n "$CF_ZONE_ID" ]]; then
                print_success "Zone ID accepted"
                echo
                break
            fi
            print_error "Zone ID cannot be empty"
        done
    fi
else
    echo "Find it at: https://dash.cloudflare.com/$DOMAIN (right sidebar)"
    echo
    while true; do
        read -p "Zone ID: " CF_ZONE_ID
        CF_ZONE_ID=$(echo "$CF_ZONE_ID" | xargs)
        
        if [[ -z "$CF_ZONE_ID" ]]; then
            print_error "Zone ID cannot be empty"
            echo
            continue
        fi
        
        if [[ ${#CF_ZONE_ID} -ne 32 ]] || [[ ! "$CF_ZONE_ID" =~ ^[a-f0-9]+$ ]]; then
            print_warning "Format looks unusual (expected 32 hex characters)"
            read -p "Continue anyway? (y/n): " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo
                continue
            fi
        fi
        
        print_success "Zone ID accepted"
        echo
        break
    done
fi

# Generate secure passwords
print_info "Generating secure passwords..."
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
WP_DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
TUNNEL_SECRET=$(openssl rand -hex 32)

# Configuration summary
echo
echo -e "${C_CYAN}╔════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_CYAN}║${C_RESET}  ${C_YELLOW}Configuration Summary${C_RESET}"
echo -e "${C_CYAN}╚════════════════════════════════════════════════════════════╝${C_RESET}"
echo "  Domain:         $DOMAIN"
echo "  Account ID:     ${CF_ACCOUNT_ID:0:8}...${CF_ACCOUNT_ID: -4}"
echo "  Zone ID:        ${CF_ZONE_ID:0:8}...${CF_ZONE_ID: -4}"
echo "  Tunnel Name:    wordpress-tunnel"
echo
read -p "Does this look correct? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    print_error "Installation cancelled by user"
    exit 0
fi

print_success "Configuration confirmed!"
sleep 2

# ==============================================================================
# STEP 2: System Update
# ==============================================================================
print_header "STEP 2: Updating System"

print_info "Updating package lists..."
apt-get update -qq || print_warning "Some package updates failed, continuing..."

print_info "Upgrading packages (this may take a few minutes)..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq || print_warning "Some upgrades failed, continuing..."

print_success "System updated"

# ==============================================================================
# STEP 3: Install Apache
# ==============================================================================
print_header "STEP 3: Installing Apache2"

print_info "Installing Apache2..."
DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 || error_exit "Failed to install Apache2"

print_info "Enabling Apache modules..."
a2enmod rewrite ssl headers expires || print_warning "Some modules may already be enabled"

print_info "Starting Apache2..."
systemctl start apache2 || print_warning "Apache may already be running"
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
DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client || error_exit "Failed to install MariaDB"

print_info "Starting MariaDB..."
systemctl start mariadb || print_warning "MariaDB may already be running"
systemctl enable mariadb
sleep 3

# Secure MariaDB
print_info "Securing MariaDB..."
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';" 2>/dev/null || \
mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$MYSQL_ROOT_PASSWORD');" 2>/dev/null || \
print_warning "Could not set root password"

mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<'EOSQL' || print_warning "Some security steps failed"
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOSQL

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
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc \
    php-soap php-intl php-zip libapache2-mod-php || error_exit "Failed to install PHP"

# Configure PHP
print_info "Configuring PHP..."
PHP_INI="/etc/php/$(php -v | grep -oP '^PHP \K[0-9]+\.[0-9]+')/apache2/php.ini"
if [[ -f "$PHP_INI" ]]; then
    cp "$PHP_INI" "$BACKUP_DIR/php.ini.bak"
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
    sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI"
    sed -i 's/memory_limit = .*/memory_limit = 256M/' "$PHP_INI"
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
else
    print_warning "Could not find PHP config, using defaults"
fi

systemctl restart apache2
print_success "PHP installed and configured"

# ==============================================================================
# STEP 6: Create WordPress Database
# ==============================================================================
print_header "STEP 6: Creating WordPress Database"

WP_DB_NAME="wordpress"
WP_DB_USER="wpuser"

print_info "Creating database: $WP_DB_NAME..."
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOSQL || error_exit "Failed to create database"
CREATE DATABASE IF NOT EXISTS $WP_DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$WP_DB_USER'@'localhost' IDENTIFIED BY '$WP_DB_PASSWORD';
GRANT ALL PRIVILEGES ON $WP_DB_NAME.* TO '$WP_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOSQL

print_success "Database created"

# ==============================================================================
# STEP 7: Install WordPress
# ==============================================================================
print_header "STEP 7: Installing WordPress"

cd /tmp
print_info "Downloading WordPress..."
wget -q --show-progress https://wordpress.org/latest.tar.gz || error_exit "Failed to download WordPress"

print_info "Extracting WordPress..."
tar -xzf latest.tar.gz

print_info "Installing WordPress files..."
if [[ -d /var/www/html ]] && [[ "$(ls -A /var/www/html 2>/dev/null)" ]]; then
    mv /var/www/html "$BACKUP_DIR/html_backup_$(date +%s)" 2>/dev/null || rm -rf /var/www/html/*
fi
mkdir -p /var/www/html
cp -r wordpress/* /var/www/html/

print_info "Configuring WordPress..."
cd /var/www/html
cp wp-config-sample.php wp-config.php

# Generate WordPress salts
SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || cat <<'EOSALTS'
define('AUTH_KEY',         'put your unique phrase here');
define('SECURE_AUTH_KEY',  'put your unique phrase here');
define('LOGGED_IN_KEY',    'put your unique phrase here');
define('NONCE_KEY',        'put your unique phrase here');
define('AUTH_SALT',        'put your unique phrase here');
define('SECURE_AUTH_SALT', 'put your unique phrase here');
define('LOGGED_IN_SALT',   'put your unique phrase here');
define('NONCE_SALT',       'put your unique phrase here');
EOSALTS
)

# Configure database settings
sed -i "s/database_name_here/$WP_DB_NAME/" wp-config.php
sed -i "s/username_here/$WP_DB_USER/" wp-config.php
sed -i "s/password_here/$WP_DB_PASSWORD/" wp-config.php

# Replace salts (safer method)
perl -i -pe "BEGIN{undef $/;} s/define\('AUTH_KEY'.*?define\('NONCE_SALT'.*?\);/$SALTS/sm" wp-config.php 2>/dev/null || \
print_warning "Could not update security keys automatically"

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

rm -f /tmp/latest.tar.gz
rm -rf /tmp/wordpress

print_success "WordPress installed"

# ==============================================================================
# STEP 8: Configure Apache
# ==============================================================================
print_header "STEP 8: Configuring Apache"

print_info "Creating virtual host..."
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
a2ensite wordpress.conf

apache2ctl configtest || print_warning "Apache config test failed, but continuing..."
systemctl restart apache2

print_success "Apache configured"

# ==============================================================================
# STEP 9: Install Cloudflared
# ==============================================================================
print_header "STEP 9: Installing Cloudflare Tunnel"

print_info "Adding Cloudflare repository..."
mkdir -p /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | \
    tee /etc/apt/sources.list.d/cloudflared.list >/dev/null

print_info "Installing cloudflared..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y cloudflared || error_exit "Failed to install cloudflared"

print_success "Cloudflared installed"

# ==============================================================================
# STEP 10: Configure Tunnel
# ==============================================================================
print_header "STEP 10: Configuring Cloudflare Tunnel"

TUNNEL_NAME="wordpress-tunnel"

print_info "Creating tunnel..."
TUNNEL_RESPONSE=$(curl -s -X POST \
    "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"name\":\"$TUNNEL_NAME\",\"tunnel_secret\":\"$TUNNEL_SECRET\"}")

TUNNEL_ID=$(echo "$TUNNEL_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)

if [[ -z "$TUNNEL_ID" ]]; then
    print_error "Failed to create tunnel"
    echo "Response: $TUNNEL_RESPONSE"
    error_exit "Could not create Cloudflare tunnel"
fi

print_success "Tunnel created: $TUNNEL_ID"

# Create credentials
mkdir -p /root/.cloudflared
cat > /root/.cloudflared/${TUNNEL_ID}.json <<EOF
{
  "AccountTag": "$CF_ACCOUNT_ID",
  "TunnelSecret": "$TUNNEL_SECRET",
  "TunnelID": "$TUNNEL_ID"
}
EOF

# Create config
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

# Configure DNS
print_info "Creating DNS records..."

# Root domain
DNS_ROOT=$(curl -s -X POST \
    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"CNAME\",\"name\":\"@\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

if echo "$DNS_ROOT" | grep -q '"success":true'; then
    print_success "DNS record created for $DOMAIN"
else
    print_warning "Failed to create root DNS record (may already exist)"
fi

# WWW subdomain
DNS_WWW=$(curl -s -X POST \
    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"CNAME\",\"name\":\"www\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

if echo "$DNS_WWW" | grep -q '"success":true'; then
    print_success "DNS record created for www.$DOMAIN"
else
    print_warning "Failed to create www DNS record (may already exist)"
fi

print_success "DNS configured"

# ==============================================================================
# STEP 11: Start Tunnel Service
# ==============================================================================
print_header "STEP 11: Starting Tunnel Service"

print_info "Installing tunnel service..."
cloudflared service install

print_info "Starting tunnel..."
systemctl start cloudflared
systemctl enable cloudflared
sleep 3

if systemctl is-active --quiet cloudflared; then
    print_success "Tunnel service running"
else
    error_exit "Tunnel failed to start"
fi

# ==============================================================================
# STEP 12: Create Summary
# ==============================================================================
print_header "STEP 12: Creating Summary"

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
Tunnel Creds:       /root/.cloudflared/${TUNNEL_ID}.json
MySQL Root Pass:    /root/.mysql_root_password
Installation Log:   $LOG_FILE

USEFUL COMMANDS
════════════════════════════════════════════════════════════
Check tunnel:       sudo systemctl status cloudflared
Tunnel logs:        sudo journalctl -u cloudflared -f
Restart tunnel:     sudo systemctl restart cloudflared
Check Apache:       sudo systemctl status apache2
Check MariaDB:      sudo systemctl status mariadb

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
print_success "Summary saved to $SUMMARY_FILE"

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
echo "   • SSL/TLS → Set to 'Full' or 'Flexible'"
echo "   • Enable 'Always Use HTTPS'"
echo
echo "2. Complete WordPress Setup:"
echo "   • Visit: https://$DOMAIN"
echo "   • Follow the setup wizard"
echo
echo "3. Install Security Plugins"
echo
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}📄 Installation Summary:${C_RESET} cat $SUMMARY_FILE"
echo -e "${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
echo
print_success "Installation completed successfully!"
echo
print_info "View logs: tail -f $LOG_FILE"
print_info "Check tunnel: sudo journalctl -u cloudflared -f"
echo
