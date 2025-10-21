#!/bin/bash
echo "🚀 HNG Stage 1 - Grace Owolabi"

read -p "Server IP: " IP
read -p "User: " USER
read -p "SSH Key: " KEY

ssh -i "$KEY" "$USER@$IP" "
# 1. CREATE APP FILES
mkdir -p /tmp/app
cat > /tmp/app/Dockerfile <<EOD
FROM node:18-alpine
WORKDIR /app
COPY . .
CMD [\"node\", \"server.js\"]
EOD

cat > /tmp/app/server.js <<EOD
const http=require('http');
http.createServer((req,res)=>{
    res.writeHead(200,{'Content-Type':'text/html'});
    res.end('<h1>🚀 HNG SUCCESS!</h1><p>Grace Owolabi</p>');
}).listen(3000);
EOD

# 2. INSTALL DOCKER + FIX PERMISSIONS
sudo apt update && sudo apt install -y docker.io nodejs
sudo usermod -aG docker $USER

# 3. RESTART DOCKER
sudo systemctl restart docker

# 4. BUILD & RUN
cd /tmp/app && 
docker build -t app . && 
docker run -d -p 3000:3000 --name app --restart always app

# 5. TEST
sleep 3 && curl -s localhost:3000
"

echo "✅ LIVE: http://$IP"
