#!/usr/bin/env bash
# ==============================================================================
# AWS EC2 Automated Setup Script for Cloud CI/CD Lab
# Target OS: Ubuntu 24.04 LTS / Ubuntu 22.04 LTS (t3.medium recommended)
# Installs: Docker CE, OpenJDK 21, Jenkins LTS, k3s Kubernetes, Nginx Reverse Proxy
# ==============================================================================
set -euo pipefail

echo "=========================================================================="
echo ">>> [1/6] Updating system packages & installing base tools..."
echo "=========================================================================="
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget git unzip python3 python3-pip python3-venv \
    apt-transport-https ca-certificates gnupg lsb-release nginx

echo "=========================================================================="
echo ">>> [2/6] Installing Docker Engine..."
echo "=========================================================================="
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
fi
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
if id "ubuntu" &>/dev/null; then
    sudo usermod -aG docker ubuntu
fi

echo "=========================================================================="
echo ">>> [3/6] Installing OpenJDK 21 and Jenkins LTS..."
echo "=========================================================================="
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jdk
if [ ! -f /usr/share/keyrings/jenkins-keyring.asc ]; then
    sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
fi
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y jenkins
sudo systemctl enable --now jenkins
sudo usermod -aG docker jenkins

echo "=========================================================================="
echo ">>> [4/6] Installing Lightweight Kubernetes (k3s)..."
echo "=========================================================================="
# Install k3s with 644 kubeconfig permissions
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

# Ensure kubectl is accessible globally in /usr/bin/kubectl
sudo ln -sf /usr/local/bin/kubectl /usr/bin/kubectl || true

# Wait for k3s cluster to initialize
echo "Waiting for Kubernetes node to be ready..."
until sudo /usr/local/bin/kubectl get nodes 2>/dev/null | grep -q "Ready"; do
    sleep 3
done
echo "Kubernetes is Ready!"

# Configure kubeconfig for ubuntu, root, and jenkins users
if id "ubuntu" &>/dev/null; then
    mkdir -p "/home/ubuntu/.kube"
    sudo cp /etc/rancher/k3s/k3s.yaml "/home/ubuntu/.kube/config"
    sudo chown -R ubuntu:ubuntu "/home/ubuntu/.kube"
fi

sudo mkdir -p /root/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /root/.kube/config

sudo mkdir -p /var/lib/jenkins/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube
sudo chmod 644 /var/lib/jenkins/.kube/config

echo "=========================================================================="
echo ">>> [5/6] Configuring Nginx Reverse Proxy for Stable Public Port 5000..."
echo "=========================================================================="
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
# Remove default site if present on port 80 to prevent conflicts
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

echo "=========================================================================="
echo ">>> [6/6] Restarting Jenkins to reload groups and environment..."
echo "=========================================================================="
sudo systemctl restart jenkins

# Wait for Jenkins to come up
echo "Waiting for Jenkins to finish initialization..."
until sudo test -f /var/lib/jenkins/secrets/initialAdminPassword; do
    sleep 2
done

echo "=========================================================================="
echo "                  AWS EC2 SETUP COMPLETED SUCCESSFULLY!                   "
echo "=========================================================================="
echo "Jenkins Unlock Password:"
echo "--------------------------------------------------------------------------"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
echo "--------------------------------------------------------------------------"
echo ""
echo "System Verification:"
echo "  Docker version:     $(docker --version)"
echo "  Kubernetes Nodes:   $(kubectl get nodes --no-headers)"
echo "  Jenkins Status:     $(systemctl is-active jenkins)"
echo "  Nginx Status:       $(systemctl is-active nginx)"
echo "=========================================================================="
