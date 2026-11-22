#!/usr/bin/env bash
# Always-on demo on a cloud VM (D62, D64: Azure for Students; steps in docs/DEPLOY.md). Run it on the VM
# (Ubuntu 24.04, x86-64 or ARM, 4 GB RAM or more) as the default user, with the VM's public IP address:
#   curl -fsSL https://raw.githubusercontent.com/f243077-cell/Roman-Urdu-Guard-Model/main/deploy/vm/setup.sh | bash -s <public-ip>
# Safe to run again (it updates the code and restarts the stack). The key and salt are made here and stay in
# ~/ru-guard/.env on the VM.
set -euo pipefail
IP="${1:?usage: setup.sh <public IP address of this VM>}"
REPO=https://github.com/f243077-cell/Roman-Urdu-Guard-Model
DIR="$HOME/ru-guard"
MODEL=ru-guard-1.5b-v2-Q4_K_M.gguf
SHA=52b5472abc1419f8c43645a733dd4dd9ee9e6e8b1be7de974d61dd988f8022e7

sudo apt-get update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q docker.io docker-compose-v2 git curl openssl iptables-persistent
# Two models plus the services need about 4 GB: a swap file keeps a 4 GB VM from running out of memory.
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap -q /swapfile && sudo swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
fi
# Some images (Oracle's Ubuntu) reject inbound traffic except SSH in iptables: open HTTP and HTTPS for Caddy.
# On Azure the network security group must also allow 80 and 443 (docs/DEPLOY.md).
for port in 80 443; do
  sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || sudo iptables -I INPUT 5 -p tcp --dport "$port" -j ACCEPT
done
sudo netfilter-persistent save

if [ -d "$DIR/.git" ]; then git -C "$DIR" pull -q; else git clone -q --depth 1 "$REPO.git" "$DIR"; fi
cd "$DIR"
[ -f "models/$MODEL" ] || curl -fL --retry 3 -o "models/$MODEL" "$REPO/releases/download/model-v1/$MODEL"
echo "$SHA  models/$MODEL" | sha256sum -c -

if [ ! -f .env ]; then
  printf 'GUARD_API_KEY=%s\nAUDIT_SALT=%s\n' "$(openssl rand -hex 24)" "$(openssl rand -hex 32)" > .env
  chmod 600 .env
fi
grep -q '^PUBLIC_HOST=' .env || echo "PUBLIC_HOST=${IP//./-}.sslip.io" >> .env
HOST="$(grep '^PUBLIC_HOST=' .env | cut -d= -f2)"

compose="sudo docker compose -f docker-compose.yml -f deploy/vm/docker-compose.cloud.yml --profile demo"
$compose up -d --build
sudo REGISTER_TARGET=docker bash scripts/register_model.sh ru-guard-1.5b-v2   # also pulls the chat model
# demo-rag indexes its documents at start and needs the guard for that: restart it once the guard answers.
for _ in $(seq 1 60); do $compose exec -T guard-api python -c "import urllib.request as u; u.urlopen('http://127.0.0.1:8001/health')" 2>/dev/null && break; sleep 5; done
$compose restart demo-rag
for _ in $(seq 1 60); do curl -sf "https://$HOST/demo/health" > /dev/null && break; sleep 10; done
curl -sf "https://$HOST/guard/health" && echo
echo "Backend: https://$HOST"
echo "Set the GitHub repository variable API_BASE to https://$HOST and run the 'pages' workflow (docs/DEPLOY.md)."
