#!/bin/bash

#================================================================
# Raspberry Pi WordPress + Cloudflare Tunnel Installer
#================================================================
# This script will:
# 1. Update the system and install Nginx, MariaDB, and PHP.
# 2. Ask for user input for domain, database, etc.
# 3. Check for Cloudflare nameservers on the domain.
# 4. Configure the database and WordPress files.
# 5. Set up the Nginx server block.
# 6. Install and configure a Cloudflare Tunnel as a service.
#================================================================

# --- Functions ---

# Function to print messages in a pretty format
print_msg() {
    echo -e "\n\n#================================================================\n# $1\n#================================================================\n"
}

# --- Script Start ---

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use 'sudo'."
  exit 1
fi

print_msg "Starting Raspberry Pi WordPress Server Setup"
sleep 2

# --- Step 1: User Input ---
print_msg "Please provide the following details"

read -p "Enter your domain name (e.g., my-awesome-site.com): " DOMAIN_NAME
read -p "Enter a name for your WordPress database (e.g., wordpress_db): " DB_NAME
read -p "Enter a username for the database (e.g., wp_user): " DB_USER
read -sp "Enter a strong password for the database user: " DB_PASS
echo

# --- Step 2: Cloudflare Nameserver Check ---
print_msg "Checking if your domain is using Cloudflare Nameservers..."
if ! dig +short NS "$DOMAIN_NAME" | grep -q "cloudflare.com"; then
    echo "ERROR: Your domain '$DOMAIN_NAME' does not appear to be using Cloudflare's nameservers."
    echo "Please log in to your domain registrar, add the domain to your Cloudflare account,"
    echo "and update the nameservers to the ones provided by Cloudflare before running this script again."
    exit 1
else
    echo "✅ Success! Cloudflare nameservers detected."
fi
sleep 2

# --- Step 3: System Update & Install Dependencies ---
print_msg "Updating system and installing required packages..."
apt update && apt upgrade -y
apt install -y nginx mariadb-server php-fpm php-mysql curl

# --- Step 4: Database Configuration ---
print_msg "Configuring MariaDB and creating the database..."
# Use a heredoc for non-interactive SQL commands
mysql -u root <<EOF
CREATE DATABASE ${DB_NAME};
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
echo "✅ Database and user created successfully."
sleep 2

# --- Step 5: Download and Configure WordPress ---
print_msg "Downloading and setting up WordPress..."
cd /var/www/
curl -O https://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz
mv wordpress "${DOMAIN_NAME}"
chown -R www-data:www-data "/var/www/${DOMAIN_NAME}"
chmod -R 755 "/var/www/${DOMAIN_NAME}"
rm latest.tar.gz
echo "✅ WordPress files are in place."
sleep 2

# --- Step 6: Configure Nginx ---
print_msg "Configuring Nginx web server..."
# Create Nginx server block file
cat > "/etc/nginx/sites-available/${DOMAIN_NAME}" <<EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};
    root /var/www/${DOMAIN_NAME};

    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock; # Check your PHP version with 'ls /var/run/php/'
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Enable the site
ln -s "/etc/nginx/sites-available/${DOMAIN_NAME}" "/etc/nginx/sites-enabled/"
# Remove default site to avoid conflicts
rm -f /etc/nginx/sites-enabled/default

# Test and reload Nginx
nginx -t
systemctl reload nginx
echo "✅ Nginx configured for ${DOMAIN_NAME}."
sleep 2

# --- Step 7: Install and Configure Cloudflare Tunnel ---
print_msg "Setting up Cloudflare Tunnel (cloudflared)..."

# Download and install cloudflared for ARM
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm
dpkg -i cloudflared.deb
rm cloudflared.deb

# Authenticate cloudflared (MANUAL STEP FOR USER)
print_msg "MANUAL STEP REQUIRED!"
echo "A browser window will open (or a URL will be displayed). Please log in to your"
echo "Cloudflare account and authorize this tunnel for your domain: ${DOMAIN_NAME}"
echo "Press ENTER to continue after you have authorized it."
cloudflared tunnel login
read -p " "

# Create the tunnel
TUNNEL_NAME="wordpress-pi"
cloudflared tunnel create $TUNNEL_NAME

# Create the configuration file
# Find the Tunnel UUID from the creation output
TUNNEL_UUID=$(cloudflared tunnel list | grep $TUNNEL_NAME | awk '{print $1}')

# Ensure the .cloudflared directory exists
mkdir -p /root/.cloudflared/

cat > /root/.cloudflared/config.yml <<EOF
tunnel: ${TUNNEL_UUID}
credentials-file: /root/.cloudflared/${TUNNEL_UUID}.json
ingress:
  - hostname: ${DOMAIN_NAME}
    service: http://localhost:80
  - service: http_status:404
EOF

# Create a DNS record for the tunnel
cloudflared tunnel route dns $TUNNEL_NAME $DOMAIN_NAME

# Install cloudflared as a systemd service to run on boot
cloudflared service install
systemctl start cloudflared

echo "✅ Cloudflare Tunnel is now running and pointing ${DOMAIN_NAME} to your Pi!"

# --- Final Message ---
print_msg "🚀 SETUP COMPLETE! 🚀"
echo "Your WordPress site is now live at: https://${DOMAIN_NAME}"
echo "Visit the URL in your browser to complete the famous 5-minute WordPress installation."
echo "When asked for database details, use the credentials you provided earlier."
echo ""
echo "Database Name: ${DB_NAME}"
echo "Database User: ${DB_USER}"
echo "Database Password: The password you entered."
echo "Database Host: localhost"
echo ""
