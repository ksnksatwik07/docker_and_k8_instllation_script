# Docker & Kubernetes Installation Script

A simple Bash script to install and configure **Docker** and **Kubernetes** on an Ubuntu Linux system.

The script installs Docker Engine, containerd, Kubernetes tools, and configures the required system settings for Kubernetes.

## Repository

**GitHub:** `ksnksatwik07/docker_and_k8_instllation_script`

## Features

This script automatically:

* Installs Docker Engine
* Installs Docker CLI
* Installs Docker Compose plugin
* Installs Docker Buildx
* Installs containerd
* Disables system swap
* Configures Kubernetes kernel modules
* Enables IP forwarding
* Configures containerd with the `systemd` cgroup driver
* Installs:

  * `kubeadm`
  * `kubelet`
  * `kubectl`
* Enables Docker, containerd, and kubelet services
* Verifies the installed versions

## Prerequisites

Before running the script, make sure you have:

* Ubuntu Linux
* `sudo` or root access
* Internet connectivity
* Minimum 2 CPUs recommended
* Minimum 2 GB RAM recommended
* At least 20 GB available disk space

> This script is intended for Ubuntu systems.

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/ksnksatwik07/docker_and_k8_instllation_script.git
```

### 2. Enter the repository

```bash
cd docker_and_k8_instllation_script
```

### 3. Make the script executable

```bash
chmod +x install-docker-k8s.sh
```

### 4. Run the installation script

```bash
sudo ./install-docker-k8s.sh
```

That's it. The script will install and configure Docker and Kubernetes automatically.

---

# What Gets Installed

After successful installation, the system will contain:

```text
Docker
├── Docker Engine
├── Docker CLI
├── Docker Buildx
└── Docker Compose

Container Runtime
└── containerd

Kubernetes
├── kubeadm
├── kubelet
└── kubectl
```

## Verify Docker

Check the Docker version:

```bash
docker --version
```

Example:

```text
Docker version 29.x.x
```

Check the Docker service:

```bash
sudo systemctl status docker
```

Test Docker:

```bash
sudo docker run hello-world
```

---

# Verify containerd

Check the containerd version:

```bash
containerd --version
```

Check the service:

```bash
sudo systemctl status containerd
```

---

# Verify Kubernetes

Check `kubeadm`:

```bash
kubeadm version
```

Check `kubectl`:

```bash
kubectl version --client
```

Check `kubelet`:

```bash
kubelet --version
```

Check the kubelet service:

```bash
sudo systemctl status kubelet
```

---

# Verify Swap

Kubernetes requires swap to be disabled by default.

Check:

```bash
swapon --show
```

If there is no output, swap is disabled.

You can also check:

```bash
free -h
```

---

# Kubernetes Cluster Initialization

The installation script installs the Kubernetes components but **does not initialize a Kubernetes cluster**.

After installation, initialize the control-plane node with:

```bash
sudo kubeadm init
```

After `kubeadm init` completes, configure `kubectl`:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Verify:

```bash
kubectl get nodes
```

## Important

A Kubernetes cluster also requires a **CNI network plugin** such as:

* Calico
* Flannel
* Cilium

The installation script currently focuses on installing the required Docker and Kubernetes components. Cluster initialization and CNI installation are separate steps.

---

# Docker Without sudo

The script adds the current user to the Docker group when possible.

After installation, log out and log back in for the group change to take effect.

Alternatively:

```bash
newgrp docker
```

Then test:

```bash
docker ps
```

> **Security note:** Membership in the Docker group effectively provides root-level access to the host. Only add trusted users.

---

# Services

The script enables and starts the following services:

```bash
sudo systemctl enable --now docker
sudo systemctl enable --now containerd
sudo systemctl enable --now kubelet
```

Check all services:

```bash
sudo systemctl status docker
sudo systemctl status containerd
sudo systemctl status kubelet
```

---

# Troubleshooting

## Docker is not running

```bash
sudo systemctl restart docker
```

Check logs:

```bash
sudo journalctl -u docker -xe
```

## containerd is not running

```bash
sudo systemctl restart containerd
```

Check logs:

```bash
sudo journalctl -u containerd -xe
```

## kubelet is not running

```bash
sudo systemctl restart kubelet
```

Check logs:

```bash
sudo journalctl -u kubelet -xe
```

## Check Kubernetes status

```bash
kubectl cluster-info
```

```bash
kubectl get nodes
```

```bash
kubectl get pods -A
```

---

# Reset Kubernetes

If you need to reset a Kubernetes node:

```bash
sudo kubeadm reset -f
```

Remove the local Kubernetes configuration:

```bash
rm -rf $HOME/.kube
```

> Use `kubeadm reset` carefully, especially on an existing cluster.

---

# Files

```text
docker_and_k8_instllation_script/
│
├── README.md
│
└── install-docker-k8s.sh
```

## Script

`install-docker-k8s.sh`

The main installation script responsible for installing and configuring Docker, containerd, and Kubernetes.

---

# Quick Installation

For users who just want to install everything:

```bash
git clone https://github.com/ksnksatwik07/docker_and_k8_instllation_script.git
cd docker_and_k8_instllation_script
chmod +x install-docker-k8s.sh
sudo ./install-docker-k8s.sh
```

## Verify

```bash
docker --version
containerd --version
kubeadm version
kubectl version --client
kubelet --version
```

---

# Notes

* This script is designed for Ubuntu.
* Internet access is required during installation.
* Kubernetes cluster initialization is not performed automatically.
* A CNI plugin must be installed before Kubernetes nodes become `Ready`.
* Review the script before running it on production systems.
* Test the script in a VM or development environment before using it in production.

---

# License

This project is provided for learning and automation purposes.

Feel free to modify and improve the script for your own environment.
