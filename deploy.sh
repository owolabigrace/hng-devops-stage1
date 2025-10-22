#!/bin/bash
set -e  # stop on first error
trap 'echo "Error occured at line $LINENO"; exit 1' ERR
LOG_FILE="deploy_$(date +%Y%m%d).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== HNG DevOps Stage 1 Automated Deployment Script ==="

# 1. Collect user inputs

# Prompt for GitHub URL
GIT_URL="https://github.com/owolabigrace/hng-devops-stage1.git"

echo "Clonign repository from $GIT_URL...."
rm -rf app
git clone "$GIT_URL" app

# Trim spaces manually (safer than tr)
GIT_URL=$(echo "$GIT_URL" | xargs)

# Validate
if [[ -z "$GIT_URL" ]]; then
  echo "Error: GitHub URL cannot be empty."
  exit 1
fi

read -p "Enter your GitHub Personal Access Token: " pat
read -p "Enter branch name (default: main): " branch
branch=${branch:-main}
read -p "Enter remote server username: " username
read -p "Enter remote server IP: " server_ip
read -p "Enter path to SSH key file: " ssh_key_path
ssh_key_path=$(eval echo "$ssh_key_path")
read -p "Enter application port: " app_port

if ! [[ "$app_port" =~ ^[0-9]+$ ]];then
     echo "Error: Port must be a number"
     exit 1
fi

# 2. Git clone operations
echo "Cloning repository..."
if [ -d "app" ]; then
    echo "Old repo exists, removing..."
    rm -rf app
fi

git clone -b "$branch" "https://${pat}@github.com/owolabigrace/hng-devops-stage1.git" app
cd app || { echo "Failed to enter repo directory"; exit 1; }

if [ ! -f Dockerfile ] && [ ! -f docker-compose.yml ]; then
    echo "No Dockerfile found, exiting."
    exit 1
fi

# 3. SSH connection test
echo "Testing SSH connection..."
ssh_key_path=$(eval echo "$ssh_key_path")
if [ ! -f "$ssh_key_path" ]; then
    echo "SSH key not found at $ssh_key_path"
    exit 1
fi

ssh -i "$ssh_key_path" -o BatchMode=yes -o ConnectTimeout=5 "$username@$server_ip" "echo 'SSH connection successful'" || {
    echo "SSH connection failed"
    exit 1
}

# 4. Prepare remote environment

ssh -i "$ssh_key_path" "$username@$server_ip" <<EOF
set -e
sudo apt update -y

# Install Docker if not installed
if ! command -v docker &> /dev/null; then
    sudo apt install -y docker.io
fi

# Install docker-compose if not installed
if ! command -v docker-compose &> /dev/null; then
    sudo apt install -y docker-compose
fi

# Install NGINX if not installed
if ! command -v nginx &> /dev/null; then
    sudo apt install -y nginx
fi

sudo systemctl enable docker
sudo systemctl start docker
sudo systemctl enable nginx
sudo systemctl start nginx
EOF

# 5. Deploy Docker app
ssh -i "$ssh_key_path" "$username@$server_ip" <<EOF
rm -rf ~/app || true
mkdir -p ~/app
EOF

scp -i "$ssh_key_path" -r . "$username@$server_ip:/home/$username/app"

ssh -i "$ssh_key_path" "$username@$server_ip" <<EOF
cd app
if docker ps -a --format '{{.Names}}' | grep -q '^myapp$'; then
    docker rm -f myapp
fi
docker build -t myapp . | tee build.log
docker run -d -p $app_port:3000 --name myapp myapp
EOF

# 6. Nginx reverse proxy

ssh -i "$ssh_key_path" "$username@$server_ip" <<EOF
sudo cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak || true
sudo bash -c 'cat > /etc/nginx/sites-available/default <<NGINX_CONF
server {
    listen 80;
    location / {
        proxy_pass http://localhost:$app_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINX_CONF'
sudo nginx -t && sudo systemctl reload nginx
EOF


ssh -i "$ssh_key_path" "$username@$server_ip" <<EOF
docker ps | grep myapp || { echo "Error: Docker container not running"; exit 1; }
systemctl is-active nginx || { echo "Error: Nginx is not active"; exit 1; }
curl -s http://localhost:$app_port | grep -q "Hello" || { echo "Error: App not responding"; exit 1; }
EOF

echo "Deployment complete. Check your app on http://$server_ip"
