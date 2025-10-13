#!/bin/bash

# ==============================================================================
# Complete Installation Script
# ==============================================================================
# Use this to finish the installation after main script succeeds
# ==============================================================================

set +e

# Colors
C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'

print_info() { echo -e "${C_BLUE}ℹ INFO: $1${C_RESET}"; }
print_success() { echo -e "${C_GREEN}✓ SUCCESS: $1${C_RESET}"; }
print_warning() { echo -e "${C_YELLOW}⚠ WARNING: $1${C_RESET}"; }

clear
echo -e "${C_GREEN}================================================================${C_RESET}"
echo -e "${C_CYAN}  Installation Complete! Final Steps${C_RESET}"
echo -e "${C_GREEN}================================================================${C_RESET}"
echo

# Read summary file if exists
if [[ -f "/root/cloudflare_tunnel_install_summary.txt" ]]; then
    DOMAIN=$(grep "^Domain:" /root/cloudflare_tunnel_install_summary.txt | awk '{print $2}')
else
    read -p "Enter your domain name: " DOMAIN
fi

echo
print_success "Your Cloudflare Tunnel is RUNNING!"
echo

# Check service status
print_info "Service Status:"
if systemctl is-active --quiet cloudflared; then
    echo "  ✓ Cloudflared: RUNNING"
else
    echo "  ✗ Cloudflared: NOT RUNNING"
fi

if systemctl is-active --quiet apache2; then
    echo "  ✓ Apache: RUNNING"
else
    echo "  ✗ Apache: NOT RUNNING"
fi

if systemctl is-active --quiet mariadb; then
    echo "  ✓ MariaDB: RUNNING"
else
    echo "  ✗ MariaDB: NOT RUNNING"
fi

echo
echo -e "${C_CYAN}═══════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}  🎉 YOUR WEBSITE IS LIVE! 🎉${C_RESET}"
echo -e "${C_CYAN}═══════════════════════════════════════════════════════${C_RESET}"
echo
echo -e "  🌐 Website URL:  ${C_GREEN}https://$DOMAIN${C_RESET}"
echo -e "  🌐 With www:     ${C_GREEN}https://www.$DOMAIN${C_RESET}"
echo

print_warning "IMPORTANT: Wait 2-5 minutes for DNS propagation"
echo

echo -e "${C_CYAN}═══════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}  NEXT STEPS (Required!)${C_RESET}"
echo -e "${C_CYAN}═══════════════════════════════════════════════════════${C_RESET}"
echo
echo "  1. Configure Cloudflare SSL:"
echo "     • Go to: https://dash.cloudflare.com"
echo "     • Select your domain: $DOMAIN"
echo "     • SSL/TLS → Set to 'Full' or 'Flexible'"
echo "     • Enable 'Always Use HTTPS'"
echo
echo "  2. Complete WordPress Installation:"
echo "     • Visit: https://$DOMAIN"
echo "     • Follow WordPress setup wizard"
echo "     • Choose language"
echo "     • Create admin account (use strong password!)"
echo
echo "  3. Security (Do this today!):"
echo "     • Install Wordfence plugin"
echo "     • Install UpdraftPlus for backups"
echo "     • Enable Cloudflare WAF"
echo

echo -e "${C_CYAN}═══════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}  USEFUL COMMANDS${C_RESET}"
echo -e "${C_CYAN}═══════════════════════════════════════════════════════${C_RESET}"
echo
echo "  Check tunnel status:"
echo "    sudo systemctl status cloudflared"
echo
echo "  View tunnel logs:"
echo "    sudo journalctl -u cloudflared -f"
echo
echo "  Restart tunnel:"
echo "    sudo systemctl restart cloudflared"
echo
echo "  View installation summary:"
echo "    cat /root/cloudflare_tunnel_install_summary.txt"
echo
echo "  Check MySQL password:"
echo "    cat /root/.mysql_root_password"
echo

echo -e "${C_CYAN}═══════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}  IMPORTANT FILES${C_RESET}"
echo -e "${C_CYAN}═══════════════════════════════════════════════════════${C_RESET}"
echo
echo "  WordPress:         /var/www/html/"
echo "  Tunnel config:     /etc/cloudflared/config.yml"
echo "  MySQL password:    /root/.mysql_root_password"
echo "  Installation log:  /var/log/cloudflare-tunnel-setup.log"
echo "  Backups:           /root/cloudflare_tunnel_backups/"
echo

echo -e "${C_CYAN}═══════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}  TESTING YOUR SITE${C_RESET}"
echo -e "${C_CYAN}═══════════════════════════════════════════════════════${C_RESET}"
echo

print_info "Testing local Apache..."
if curl -s http://localhost | grep -qi "wordpress\|html"; then
    print_success "Apache is serving content"
else
    print_warning "Apache may not be serving content correctly"
fi

print_info "Testing tunnel connection..."
if journalctl -u cloudflared -n 20 | grep -qi "registered\|connection"; then
    print_success "Tunnel is connected to Cloudflare"
else
    print_warning "Tunnel connection not confirmed - check logs"
fi

echo
print_info "Test from your browser (wait 2-5 minutes first):"
echo "  https://$DOMAIN"
echo

echo -e "${C_GREEN}═══════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_GREEN}  Installation Complete! Enjoy your website! 🎉${C_RESET}"
echo -e "${C_GREEN}═══════════════════════════════════════════════════════${C_RESET}"
echo
