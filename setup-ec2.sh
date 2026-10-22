#!/usr/bin/env bash
# ==============================================================================
# Universal AWS EC2 Setup Script for Cloud CI/CD Lab
# Supports: Amazon Linux 2023, Amazon Linux 2, Ubuntu 24.04, Ubuntu 22.04
# Installs: Docker, Java 21, Jenkins LTS, k3s Kubernetes, Nginx Reverse Proxy
# ==============================================================================
set -euo pipefail

echo ">>> [1/6] Detecting operating system..."
OS_ID="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"
fi
echo "Detected OS: $OS_ID ($PRETTY_NAME)"

echo ">>> [2/6] Installing dependencies and Docker Engine..."
if [ "$OS_ID" = "amzn" ] || [ "$OS_ID" = "fedora" ] || [ "$OS_ID" = "rhel" ]; then
    sudo dnf update -y
    sudo dnf install -y git curl wget unzip python3 python3-pip iptables nginx
    sudo dnf install -y docker
    sudo systemctl enable --now docker
    if id "ec2-user" &>/dev/null; then
        sudo usermod -aG docker ec2-user
    fi
elif [ "$OS_ID" = "ubuntu" ] || [ "$OS_ID" = "debian" ]; then
    sudo apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl wget git unzip python3 python3-pip python3-venv \
        apt-transport-https ca-certificates gnupg lsb-release nginx
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
fi

echo ">>> [3/6] Installing Java 21 and Jenkins LTS..."
if [ "$OS_ID" = "amzn" ] || [ "$OS_ID" = "fedora" ] || [ "$OS_ID" = "rhel" ]; then
    sudo dnf install -y java-21-amazon-corretto
    sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    sudo dnf install -y jenkins
    sudo systemctl enable --now jenkins
    sudo usermod -aG docker jenkins
elif [ "$OS_ID" = "ubuntu" ] || [ "$OS_ID" = "debian" ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jdk
    if [ ! -f /usr/share/keyrings/jenkins-keyring.asc ]; then
        sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
    fi
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
    sudo apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y jenkins
    sudo systemctl enable --now jenkins
    sudo usermod -aG docker jenkins
fi

echo ">>> [4/6] Installing Lightweight Kubernetes (k3s)..."
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
sudo ln -sf /usr/local/bin/kubectl /usr/bin/kubectl || true

echo "Waiting for Kubernetes node to be ready..."
until sudo /usr/local/bin/kubectl get nodes 2>/dev/null | grep -q "Ready"; do
    sleep 3
done
echo "Kubernetes is Ready!"

# Configure kubeconfig for all standard users
for U in ec2-user ubuntu root; do
    if [ "$U" = "root" ]; then
        U_HOME="/root"
    else
        U_HOME="/home/$U"
    fi
    if [ -d "$U_HOME" ]; then
        mkdir -p "$U_HOME/.kube"
        sudo cp /etc/rancher/k3s/k3s.yaml "$U_HOME/.kube/config"
        sudo chown -R $U:$U "$U_HOME/.kube" 2>/dev/null || true
        sudo chmod 600 "$U_HOME/.kube/config" 2>/dev/null || true
    fi
done

sudo mkdir -p /var/lib/jenkins/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube
sudo chmod 644 /var/lib/jenkins/.kube/config

echo ">>> [5/6] Configuring Nginx Reverse Proxy for Public Port 5000..."
NGINX_CONF_DIR="/etc/nginx/conf.d"
mkdir -p "$NGINX_CONF_DIR"

sudo tee "$NGINX_CONF_DIR/cloud-cicd.conf" > /dev/null << 'EOF'
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

# For Ubuntu/Debian compatibility with sites-enabled
if [ -d /etc/nginx/sites-available ]; then
    sudo ln -sf "$NGINX_CONF_DIR/cloud-cicd.conf" /etc/nginx/sites-available/cloud-cicd || true
    sudo ln -sf /etc/nginx/sites-available/cloud-cicd /etc/nginx/sites-enabled/cloud-cicd || true
    sudo rm -f /etc/nginx/sites-enabled/default || true
fi

sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

echo ">>> [6/6] Restarting Jenkins to apply group memberships..."
sudo systemctl restart jenkins

echo "Waiting for Jenkins to initialize..."
until sudo test -f /var/lib/jenkins/secrets/initialAdminPassword; do
    sleep 2
done

echo "=========================================================================="
echo "                  AWS EC2 SETUP COMPLETED SUCCESSFULLY!                   "
echo "=========================================================================="
echo "Jenkins Initial Admin Password:"
echo "--------------------------------------------------------------------------"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
echo "--------------------------------------------------------------------------"
echo ""
echo "System Verification:"
echo "  OS:                 $PRETTY_NAME"
echo "  Docker version:     $(docker --version)"
echo "  Kubernetes Nodes:   $(kubectl get nodes --no-headers)"
echo "  Jenkins Status:     $(systemctl is-active jenkins)"
echo "  Nginx Status:       $(systemctl is-active nginx)"
echo "=========================================================================="
