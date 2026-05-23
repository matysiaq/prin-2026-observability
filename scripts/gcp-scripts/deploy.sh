#!/bin/bash
# deploy.sh — provisions a 3-node GCP cluster via Terraform and configures
# Kubernetes via Ansible, driven by config.yaml.
#
# Usage:  ./deploy.sh [--skip-terraform] [--skip-ansible]
#   --skip-terraform   Re-use existing Terraform state (VMs already exist)
#   --skip-ansible     Only provision the VMs, skip Kubernetes setup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.yaml"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"

SKIP_TERRAFORM=false
SKIP_ANSIBLE=false
for arg in "$@"; do
  case $arg in
    --skip-terraform) SKIP_TERRAFORM=true ;;
    --skip-ansible)   SKIP_ANSIBLE=true ;;
  esac
done

# ── helpers ───────────────────────────────────────────────────────────────────

cfg() {
  python3 - "$CONFIG" "$1" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    c = yaml.safe_load(f)
keys = sys.argv[2].split('.')
v = c
for k in keys:
    v = v[k]
print('' if v is None else v)
PYEOF
}

log() { echo "==> $*"; }

# ── validate / auto-install deps ──────────────────────────────────────────────

for cmd in python3 terraform gcloud; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' not found in PATH" >&2
    echo "       Run this script inside GCP Cloud Shell where gcloud and terraform are pre-installed." >&2
    exit 1
  fi
done

python3 -c "import yaml" 2>/dev/null || {
  log "Installing pyyaml..."
  pip install --quiet --user pyyaml
}

if ! command -v ansible-playbook &>/dev/null; then
  log "Ansible not found — installing (this takes ~1 minute)..."
  pip install --quiet --user ansible
  export PATH="$HOME/.local/bin:$PATH"
fi

# ── verify GCP login ──────────────────────────────────────────────────────────

log "Verifying GCP login..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q '@'; then
  echo "ERROR: No active GCP account found." >&2
  echo "       In Cloud Shell you should already be logged in." >&2
  echo "       If not, run: gcloud auth login" >&2
  exit 1
fi

# ── read config ───────────────────────────────────────────────────────────────

log "Reading config.yaml..."

CLUSTER_NAME=$(cfg cluster.name)
K8S_VERSION=$(cfg kubernetes.version)
POD_CIDR=$(cfg kubernetes.pod_cidr)
SERVICE_CIDR=$(cfg kubernetes.service_cidr)
CILIUM_VERSION=$(cfg cni.version)

GCP_PROJECT=$(cfg gcp.project)
GCP_REGION=$(cfg gcp.region)
GCP_ZONE=$(cfg gcp.zone)
MASTER_MACHINE_TYPE=$(cfg gcp.master_machine_type)
WORKER_MACHINE_TYPE=$(cfg gcp.worker_machine_type)
WORKER_COUNT=$(cfg gcp.worker_count)
DISK_SIZE=$(cfg gcp.disk_size_gb)

SSH_PUB_KEY_PATH=$(cfg ssh.public_key_path)
SSH_KEY_PATH=$(cfg ssh.private_key_path)
SSH_USER=$(cfg ssh.user)

HELM_VERSION="4.0.4"

# Expand ~ in paths
SSH_PUB_KEY_PATH="${SSH_PUB_KEY_PATH/#\~/$HOME}"
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

if [[ "$GCP_PROJECT" == "TODO:"* ]]; then
  echo "ERROR: Please set your GCP project ID in config.yaml (gcp.project)" >&2
  exit 1
fi

if [[ ! -f "$SSH_PUB_KEY_PATH" ]]; then
  echo "ERROR: SSH public key not found at: $SSH_PUB_KEY_PATH" >&2
  echo "       Generate one with: ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N \"\"" >&2
  exit 1
fi

SSH_PUB_KEY=$(cat "$SSH_PUB_KEY_PATH")

# Derive apt package version and minor tag (e.g. "1.30.0" → "1.30.0-1.1" / "v1.30")
K8S_PKG_VERSION="${K8S_VERSION}-1.1"
K8S_MINOR="v$(echo "$K8S_VERSION" | cut -d. -f1,2)"

# Enable Compute Engine API (safe to call even if already enabled)
log "Enabling Compute Engine API..."
gcloud services enable compute.googleapis.com --project="$GCP_PROJECT" --quiet

# ── step 1: terraform ─────────────────────────────────────────────────────────

if [[ "$SKIP_TERRAFORM" == "true" ]]; then
  log "Skipping Terraform (--skip-terraform)."
  cd "$TERRAFORM_DIR"
else
  log "Generating terraform.tfvars..."
  cat > "$TERRAFORM_DIR/terraform.tfvars" <<TFVARS
project             = "$GCP_PROJECT"
region              = "$GCP_REGION"
zone                = "$GCP_ZONE"
cluster_name        = "$CLUSTER_NAME"
master_machine_type = "$MASTER_MACHINE_TYPE"
worker_machine_type = "$WORKER_MACHINE_TYPE"
worker_count        = $WORKER_COUNT
disk_size_gb        = $DISK_SIZE
ssh_user            = "$SSH_USER"
ssh_public_key      = "$SSH_PUB_KEY"
TFVARS

  log "Provisioning GCP VMs with Terraform..."
  cd "$TERRAFORM_DIR"
  terraform init -input=false
  terraform apply -auto-approve -input=false
fi

MASTER_IP=$(terraform output -raw master_public_ip)
WORKER_IPS=$(terraform output -json worker_public_ips | python3 -c "import sys,json; print('\n'.join(json.load(sys.stdin)))")

# ── step 2: ansible inventory ─────────────────────────────────────────────────

log "Generating Ansible inventory..."
mkdir -p "$ANSIBLE_DIR"

{
  echo "[masters]"
  echo "master ansible_host=${MASTER_IP} ansible_user=${SSH_USER} ansible_ssh_private_key_file=${SSH_KEY_PATH}"
  echo ""
  echo "[workers]"
  IDX=1
  while IFS= read -r ip; do
    echo "worker-${IDX} ansible_host=${ip} ansible_user=${SSH_USER} ansible_ssh_private_key_file=${SSH_KEY_PATH}"
    IDX=$((IDX + 1))
  done <<< "$WORKER_IPS"
  echo ""
  echo "[all:vars]"
  echo "ansible_python_interpreter=/usr/bin/python3"
} > "$ANSIBLE_DIR/inventory"

# ── step 3: group_vars/all.yaml ───────────────────────────────────────────────

log "Generating Ansible group_vars..."
mkdir -p "$ANSIBLE_DIR/group_vars"
mkdir -p "$ANSIBLE_DIR/kubeconfigs"

cat > "$ANSIBLE_DIR/group_vars/all.yaml" <<VARS
# Auto-generated by deploy.sh — do not edit manually; re-run deploy.sh instead
cluster_name: "${CLUSTER_NAME}"
cluster_topology: "multi-node"
k8s_version: "${K8S_PKG_VERSION}"
k8s_minor: "${K8S_MINOR}"
pod_cidr: "${POD_CIDR}"
service_cidr: "${SERVICE_CIDR}"
cilium_helm_version: "${CILIUM_VERSION}"
helm_version: "${HELM_VERSION}"
k8s_user: "${SSH_USER}"
master_ip: "${MASTER_IP}"
VARS

# ── step 4: ansible playbooks ─────────────────────────────────────────────────

if [[ "$SKIP_ANSIBLE" == "true" ]]; then
  log "Skipping Ansible (--skip-ansible)."
  exit 0
fi

log "Waiting for SSH to become available on all nodes..."
ALL_IPS=("$MASTER_IP")
while IFS= read -r ip; do
  ALL_IPS+=("$ip")
done <<< "$WORKER_IPS"

for ip in "${ALL_IPS[@]}"; do
  TIMEOUT=180
  ELAPSED=0
  until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
        -i "${SSH_KEY_PATH}" "${SSH_USER}@${ip}" true 2>/dev/null; do
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
      echo "ERROR: SSH not available on ${ip} after ${TIMEOUT}s" >&2
      exit 1
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
  done
  log "SSH up on ${ip} (${ELAPSED}s elapsed)."
done

log "Running Ansible playbooks..."
cd "$ANSIBLE_DIR"
export ANSIBLE_HOST_KEY_CHECKING=False
export PATH="$HOME/.local/bin:$PATH"

ansible-playbook -i inventory playbooks/01-base-setup.yaml
ansible-playbook -i inventory playbooks/02-kube-dependencies.yaml
ansible-playbook -i inventory playbooks/03-init-master.yaml

log "Waiting 20s for cluster to stabilise..."
sleep 20

ansible-playbook -i inventory playbooks/04-join-workers.yaml
ansible-playbook -i inventory playbooks/05-fetch-kubeconfig.yaml

# ── done ──────────────────────────────────────────────────────────────────────

KUBECONFIG_PATH="$ANSIBLE_DIR/kubeconfigs/${CLUSTER_NAME}.config"
echo ""
echo "============================================================"
echo "  Cluster '${CLUSTER_NAME}' is ready!"
echo "  Mode:       3-node (1 master + ${WORKER_COUNT} workers, e2-standard-2)"
echo "  Kubeconfig: ${KUBECONFIG_PATH}"
echo ""
echo "  To use:"
echo "    export KUBECONFIG=${KUBECONFIG_PATH}"
echo "    kubectl get nodes"
echo "============================================================"
