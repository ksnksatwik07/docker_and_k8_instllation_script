```bash
#!/usr/bin/env bash

# ============================================================
# Docker + Kubernetes Installation Script
# Target: AWS EC2 Ubuntu
# ============================================================

set -Eeuo pipefail

K8S_MINOR="v1.37"

echo "=================================================="
echo " Docker + Kubernetes Installation"
echo " AWS EC2 Ubuntu"
echo " Kubernetes: ${K8S_MINOR}"
echo "=================================================="

# ------------------------------------------------------------
# Check root
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Please run this script with sudo."
    echo
    echo "Usage:"
    echo "  sudo ./install-docker-k8s.sh"
    exit 1
fi

# ------------------------------------------------------------
# Detect the actual login user
# ------------------------------------------------------------

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="${SUDO_USER}"
else
    TARGET_USER="$(logname 2>/dev/null || echo ubuntu)"
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

echo
echo "Target user: ${TARGET_USER}"
echo "Home directory: ${TARGET_HOME}"
echo

# ------------------------------------------------------------
# Check Ubuntu
# ------------------------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Cannot determine operating system."
    exit 1
fi

source /etc/os-release

if [[ "${ID}" != "ubuntu" ]]; then
    echo "ERROR: This script is designed for Ubuntu."
    echo "Detected: ${PRETTY_NAME}"
    exit 1
fi

echo "Detected OS: ${PRETTY_NAME}"

# ------------------------------------------------------------
# 1. Update system
# ------------------------------------------------------------

echo
echo "[1/10] Updating system..."

apt-get update -y

apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    apt-transport-https \
    software-properties-common

# ------------------------------------------------------------
# 2. Disable swap
# ------------------------------------------------------------

echo
echo "[2/10] Disabling swap..."

swapoff -a || true

# Remove active swap entries from fstab
sed -i '/[[:space:]]swap[[:space:]]/ s/^/#/' /etc/fstab

if swapon --show | grep -q .; then
    echo "ERROR: Swap is still enabled."
    exit 1
fi

echo "Swap disabled successfully."

# ------------------------------------------------------------
# 3. Install Docker
# ------------------------------------------------------------

echo
echo "[3/10] Installing Docker..."

install -m 0755 -d /etc/apt/keyrings

curl -fsSL \
    https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update -y

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# ------------------------------------------------------------
# 4. Start Docker
# ------------------------------------------------------------

echo
echo "[4/10] Starting Docker..."

systemctl enable docker
systemctl start docker

if ! systemctl is-active --quiet docker; then
    echo "ERROR: Docker service is not running."
    systemctl status docker --no-pager || true
    exit 1
fi

echo "Docker service is running."

# ------------------------------------------------------------
# 5. Configure Docker for non-root user
# ------------------------------------------------------------

echo
echo "[5/10] Configuring Docker for ${TARGET_USER}..."

if ! getent group docker >/dev/null; then
    groupadd docker
fi

usermod -aG docker "${TARGET_USER}"

# Make sure the Docker socket has the correct group
chown root:docker /var/run/docker.sock
chmod 660 /var/run/docker.sock

echo "User ${TARGET_USER} added to docker group."

# ------------------------------------------------------------
# 6. Test Docker as the EC2 user
# ------------------------------------------------------------

echo
echo "[6/10] Testing Docker without sudo..."

# Use sg so the current session immediately gets docker group access.
DOCKER_TEST=$(su - "${TARGET_USER}" -c \
    "sg docker -c 'docker version --format \"{{.Server.Version}}\"'")

if [[ -z "${DOCKER_TEST}" ]]; then
    echo "ERROR: Docker cannot be accessed without sudo."
    exit 1
fi

echo "Docker server version: ${DOCKER_TEST}"

echo
echo "Running Docker hello-world test..."

su - "${TARGET_USER}" -c \
    "sg docker -c 'docker run --rm hello-world >/tmp/docker-hello.log 2>&1'"

if ! grep -q "Hello from Docker!" /tmp/docker-hello.log; then
    echo "ERROR: Docker hello-world test failed."
    cat /tmp/docker-hello.log
    exit 1
fi

echo "Docker non-root test successful."

# ------------------------------------------------------------
# 7. Configure containerd for Kubernetes
# ------------------------------------------------------------

echo
echo "[7/10] Configuring containerd..."

mkdir -p /etc/containerd

containerd config default > /etc/containerd/config.toml

# Kubernetes recommends systemd cgroups when using systemd-based Linux.
sed -i \
    's/SystemdCgroup = false/SystemdCgroup = true/' \
    /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

if ! systemctl is-active --quiet containerd; then
    echo "ERROR: containerd is not running."
    systemctl status containerd --no-pager || true
    exit 1
fi

echo "containerd is running."

# ------------------------------------------------------------
# 8. Configure Kubernetes networking
# ------------------------------------------------------------

echo
echo "[8/10] Configuring Kubernetes networking..."

cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system >/dev/null

echo "Kubernetes networking configuration applied."

# ------------------------------------------------------------
# 9. Install Kubernetes
# ------------------------------------------------------------

echo
echo "[9/10] Installing Kubernetes ${K8S_MINOR}..."

mkdir -p -m 755 /etc/apt/keyrings

curl -fsSL \
    "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" |
    gpg --dearmor \
    -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat > /etc/apt/sources.list.d/kubernetes.list <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /
EOF

apt-get update -y

apt-get install -y \
    kubelet \
    kubeadm \
    kubectl

apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

echo "Kubernetes packages installed."

# ------------------------------------------------------------
# 10. Verify everything
# ------------------------------------------------------------

echo
echo "[10/10] Verifying installation..."

echo
echo "---------------- Docker ----------------"

docker --version

echo
echo "---------------- Docker Compose ----------------"

su - "${TARGET_USER}" -c \
    "sg docker -c 'docker compose version'"

echo
echo "---------------- containerd ----------------"

containerd --version

echo
echo "---------------- kubeadm ----------------"

kubeadm version

echo
echo "---------------- kubelet ----------------"

kubelet --version

echo
echo "---------------- kubectl ----------------"

su - "${TARGET_USER}" -c \
    "kubectl version --client"

# ------------------------------------------------------------
# Final service checks
# ------------------------------------------------------------

echo
echo "Checking services..."

if ! systemctl is-active --quiet docker; then
    echo "ERROR: Docker service check failed."
    exit 1
fi

if ! systemctl is-active --quiet containerd; then
    echo "ERROR: containerd service check failed."
    exit 1
fi

# ------------------------------------------------------------
# Final Docker non-root verification
# ------------------------------------------------------------

echo
echo "Final Docker non-root verification..."

su - "${TARGET_USER}" -c \
    "sg docker -c 'docker ps'"

echo
echo "=================================================="
echo " INSTALLATION SUCCESSFUL"
echo "=================================================="

echo
echo "Docker:"
echo "  docker --version"

echo
echo "Docker Compose:"
echo "  docker compose version"

echo
echo "Kubernetes:"
echo "  kubeadm version"
echo "  kubelet --version"
echo "  kubectl version --client"

echo
echo "Docker can be used without sudo by:"
echo "  ${TARGET_USER}"

echo
echo "IMPORTANT:"
echo "Log out and log back in before using Docker normally."
echo
echo "Then test:"
echo "  docker ps"
echo "  docker run hello-world"
echo
echo "Kubernetes components are installed."
echo "A Kubernetes cluster has NOT been initialized yet."
echo
echo "To initialize a control-plane:"
echo "  sudo kubeadm init"
echo
echo "=================================================="
```
