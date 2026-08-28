#!/usr/bin/env bash
set -euo pipefail

echo "======================================"
echo " Docker + Kubernetes Installation"
echo "======================================"

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root or with sudo:"
    echo "  sudo bash $0"
    exit 1
fi

# --------------------------------------
# 1. Disable swap
# --------------------------------------
echo "[1/7] Disabling swap..."

swapoff -a
sed -i '/\sswap\s/s/^/#/' /etc/fstab


# --------------------------------------
# 2. Install prerequisites
# --------------------------------------
echo "[2/7] Installing prerequisites..."

apt-get update
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    apt-transport-https


# --------------------------------------
# 3. Install Docker Engine
# --------------------------------------
echo "[3/7] Installing Docker..."

install -m 0755 -d /etc/apt/keyrings

curl -fsSL \
    https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

systemctl enable --now docker


# --------------------------------------
# 4. Configure containerd for Kubernetes
# --------------------------------------
echo "[4/7] Configuring containerd..."

mkdir -p /etc/containerd

containerd config default > /etc/containerd/config.toml

# Enable systemd cgroup driver
sed -i \
    's/SystemdCgroup = false/SystemdCgroup = true/' \
    /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd


# --------------------------------------
# 5. Kubernetes kernel/network settings
# --------------------------------------
echo "[5/7] Configuring Kubernetes networking..."

cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system


# --------------------------------------
# 6. Install Kubernetes
# --------------------------------------
echo "[6/7] Installing Kubernetes..."

K8S_MINOR="v1.37"

mkdir -p -m 755 /etc/apt/keyrings

curl -fsSL \
    "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" |
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat > /etc/apt/sources.list.d/kubernetes.list <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /
EOF

apt-get update

apt-get install -y \
    kubelet \
    kubeadm \
    kubectl

apt-mark hold kubelet kubeadm kubectl

systemctl enable --now kubelet


# --------------------------------------
# 7. Docker user configuration
# --------------------------------------
echo "[7/7] Configuring Docker access..."

if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$(logname 2>/dev/null || echo root)"
fi

if [[ "$REAL_USER" != "root" ]]; then
    usermod -aG docker "$REAL_USER"
fi


# --------------------------------------
# Verification
# --------------------------------------
echo ""
echo "======================================"
echo " Installation Complete!"
echo "======================================"

echo ""
echo "Docker:"
docker --version

echo ""
echo "Containerd:"
containerd --version

echo ""
echo "Kubernetes:"
kubeadm version
kubectl version --client
kubelet --version

echo ""
echo "Swap:"
swapon --show || true

echo ""
echo "======================================"
echo " IMPORTANT"
echo "======================================"
echo ""
echo "Docker + Kubernetes packages are installed."
echo ""
echo "For a SINGLE-NODE control-plane cluster:"
echo ""
echo "  sudo kubeadm init --pod-network-cidr=10.244.0.0/16"
echo ""
echo "Then configure kubectl:"
echo ""
echo "  mkdir -p \$HOME/.kube"
echo "  sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config"
echo "  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
echo ""
echo "You will also need to install a CNI plugin such as Flannel or Calico."
echo ""
echo "If you want Docker commands without sudo, log out and back in."
echo ""
