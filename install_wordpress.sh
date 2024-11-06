#!/bin/bash

# WordPress Installation Script for Ubuntu 24.04 with Nginx

# Functions
generate_random_password() {
    # Generate a random password of at least 12 characters
    tr -dc 'A-Za-z0-9!@#$%^&*()-_=+' </dev/urandom | head -c 12
}

# Prompt for database name with default "wp"
read -p "Enter the name of the database (default: wp): " DB_NAME
DB_NAME=${DB_NAME:-wp}

# Prompt for database user with default "wp_user"
read -p "Enter the database username (default: wp_user): " DB_USER
DB_USER=${DB_USER:-wp_user}

# Prompt for database password with a generated default
DEFAULT_DB_PASSWORD=$(generate_random_password)
read -p "Enter the database password (default: $DEFAULT_DB_PASSWORD): " DB_PASSWORD
DB_PASSWORD=${DB_PASSWORD:-$DEFAULT_DB_PASSWORD}

# Prompt for URL with cleaning of protocol and www prefix
read -p "Enter the domain name (e.g., example.com): " DOMAIN_NAME
DOMAIN_NAME=$(echo "$DOMAIN_NAME" | sed -E 's~^(https?://)?(www\.)?~~g')

# Extract the URL without TLD for the WordPress path
SITE_NAME=$(echo "$DOMAIN_NAME" | sed -E 's/\.[^.]+$//')
WORDPRESS_PATH="/var/www/$SITE_NAME"

# Variables
NGINX_CONF="/etc/nginx/sites-available/$SITE_NAME"
SERVER_IP=$(hostname -I | awk '{print $1}')  # Automatically gets the server's IP address

# Step 1: Update and upgrade the system
echo "Updating system packages..."
sudo apt update && sudo apt-get upgrade -y && sudo apt autoremove -y

# Step 2: Install Nginx
echo "Installing Nginx..."
sudo apt install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx
sudo systemctl status nginx --no-pager

# Step 3: Install PHP and required extensions
echo "Installing PHP and extensions..."
sudo apt install php php-cli php-common php-imap php-fpm php-snmp php-xml php-zip php-mbstring php-curl php-mysqli php-gd php-intl unzip vim -y
sudo apt purge apache2 -y
php -v

# Step 4: Install MariaDB and secure it with unix_socket authentication
echo "Installing MariaDB..."
sudo apt install mariadb-server -y
sudo systemctl start mariadb
sudo systemctl enable mariadb
sudo systemctl status mariadb --no-pager

# Automating MariaDB secure installation steps with unix_socket authentication for root
echo "Securing MariaDB installation with unix_socket authentication..."
sudo mariadb -u root <<EOF
-- Set root authentication to unix_socket
ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Disallow root login remotely
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Remove test database
DROP DATABASE IF EXISTS test;

-- Reload privilege tables
FLUSH PRIVILEGES;
EOF

echo "MariaDB secure installation with unix_socket authentication completed automatically."

# Step 5: Create WordPress database and user
echo "Creating WordPress database and user..."
sudo mariadb -u root <<MYSQL_SCRIPT
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
CREATE DATABASE $DB_NAME;
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EXIT;
MYSQL_SCRIPT

# Step 6: Download and Install WordPress
echo "Downloading WordPress..."
cd /tmp/ && wget https://wordpress.org/latest.zip
sudo unzip latest.zip -d /var/www

# Move and rename the WordPress installation folder
sudo mv /var/www/wordpress $WORDPRESS_PATH
echo "Setting permissions for WordPress..."
sudo chown -R www-data:www-data $WORDPRESS_PATH

# Configure wp-config.php
echo "Configuring WordPress database settings..."
sudo mv $WORDPRESS_PATH/wp-config-sample.php $WORDPRESS_PATH/wp-config.php
sudo sed -i "s/database_name_here/$DB_NAME/" $WORDPRESS_PATH/wp-config.php
sudo sed -i "s/username_here/$DB_USER/" $WORDPRESS_PATH/wp-config.php
sudo sed -i "s/password_here/$DB_PASSWORD/" $WORDPRESS_PATH/wp-config.php

# Step 7: Create Nginx Server Block for WordPress with IP alias
echo "Creating Nginx server block..."
sudo tee $NGINX_CONF > /dev/null <<EOL
server {
    listen 80;
    server_name $DOMAIN_NAME $SERVER_IP;

    root $WORDPRESS_PATH;
    index index.php;

    server_tokens off;

    access_log /var/log/nginx/${SITE_NAME}_access.log;
    error_log /var/log/nginx/${SITE_NAME}_error.log;

    client_max_body_size 64M;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include /etc/nginx/fastcgi.conf;
    }
}
EOL

# Step 8: Enable the WordPress site in Nginx
echo "Enabling WordPress Nginx configuration..."
sudo ln -s $NGINX_CONF /etc/nginx/sites-enabled/

# Restart Nginx to apply changes
echo "Restarting Nginx..."
sudo systemctl restart nginx

# Clean up
echo "Cleaning up unused packages and cache..."
sudo apt autoremove -y
sudo apt autoclean -y

echo "WordPress installation completed successfully!"
