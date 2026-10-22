#!/usr/bin/env bash
# ==============================================================================
# AWS EC2 Automated Setup Script for Cloud CI/CD Lab
# Target OS: Ubuntu 24.04 LTS / Ubuntu 22.04 LTS (t3.medium recommended)
# Installs: Docker, Java 21, Jenkins LTS, k3s (Lightweight Kubernetes), Nginx
# ==============================================================================
set -euo pipefail

echo ">>> [1/6] Updating system packages..."
sudo apt-get update -y
sudo apt-get install -y curl wget git unzip python3 python3-pip python3-venv apt-transport-https ca-certificates gnupg lsb-release nginx

echo ">>> [2/6] Installing Docker Engine..."
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
fi
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker ubuntu

echo ">>> [3/6] Installing OpenJDK 21 and Jenkins LTS..."
sudo apt-get install -y openjdk-21-jdk
if [ ! -f /usr/share/keyrings/jenkins-keyring.asc ]; then
    sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
fi
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y jenkins
sudo systemctl enable --now jenkins
sudo usermod -aG docker jenkins

echo ">>> [4/6] Installing Lightweight Kubernetes (k3s)..."
# Install k3s with accessible kubeconfig mode
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

# Configure kubeconfig for the jenkins and ubuntu users
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown $(id -u):$(id -g) "$HOME/.kube/config"

sudo mkdir -p /var/lib/jenkins/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube

echo ">>> [5/6] Configuring Nginx Reverse Proxy for Public Port 5000..."
sudo tee /etc/nginx/sites-available/cloud-cicd > /dev/null << 'EOF'
server {
    listen 5000 default_server;
    listen [::]:5000 default_server;

    server_name _;

    location / {
        proxy_pass http://127.0.0.1:30080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 5s;
        proxy_read_timeout 60s;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/cloud-cicd /etc/nginx/sites-enabled/cloud-cicd
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

echo ">>> [6/6] Restarting Jenkins to apply group memberships..."
sudo systemctl restart jenkins

echo "=========================================================================="
echo " SETUP COMPLETED SUCCESSFULLY!"
echo "=========================================================================="
echo "Jenkins Initial Admin Password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
echo ""
echo "Verify status:"
echo "  - Docker:     docker --version"
echo "  - Kubernetes: kubectl get nodes"
echo "  - Jenkins:    sudo systemctl status jenkins"
echo "  - Nginx:      sudo systemctl status nginx"
echo "=========================================================================="
