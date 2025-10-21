#!/bin/bash
set -e  # stop on first error
LOG_FILE="deploy_$(date +%Y%m%d).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== HNG DevOps Stage 1 Automated Deployment Script ==="

# 1. Collect user inputs
read -p "Enter GitHub repo URL: " repo_url
read -p "Enter your GitHub Personal Access Token: " pat
read -p "Enter branch name (default: main): " branch
branch=${branch:-main}
read -p "Enter remote server username: " username
read -p "Enter remote server IP: " server_ip
read -p "Enter path to SSH key file: " ssh_key_path
ssh_key_path=$(eval echo "$ssh_key_path")
read -p "Enter application port: " app_port

# 2. Git clone operations
echo "Cloning repository..."
if [ -d "app" ]; then
    echo "Old repo exists, removing..."
    rm -rf app
fi

git clone -b "$branch" "https://${pat}@${repo_url#https://}" app
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
  sudo apt update -y
  sudo apt install -y docker.io docker-compose nginx
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo usermod -aG docker \$USER
  sudo systemctl enable nginx
  sudo systemctl start nginx
EOF

# 5. Deploy Docker app
scp -i "$ssh_key_path" -r . "$username@$server_ip:/home/$username/app"
ssh -i "$ssh_key_path" "$username@$server_ip" <<EOF
  cd app
  docker build -t myapp .
  docker run -d -p 80:$app_port myapp
EOF

# 6. Nginx reverse proxy
ssh -i "$ssh_key_path" "$username@$server_ip" <<EOF
  sudo bash -c 'cat > /etc/nginx/sites-available/default <<NGINX_CONF
server {
    listen 80;
    location / {
        proxy_pass http://localhost:$app_port;
    }
}
NGINX_CONF'
  sudo nginx -t && sudo systemctl reload nginx
EOF

echo "Deployment complete. Check your app on http://$server_ip"
