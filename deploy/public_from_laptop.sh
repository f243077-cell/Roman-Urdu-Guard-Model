#!/usr/bin/env bash
# Public demo from this laptop (D61): the proxy (deploy/proxy.py) serves the keyless web build and forwards to the
# local stack; a free Cloudflare quick tunnel gives it a public https address. Works only while the laptop and
# this script run; the address changes at every start.
#   Needs: Ollama with the models, and the stack started with
#     RATE_LIMIT=100000/minute ALLOW_GUARD_TOGGLE=true docker compose -f docker-compose.yml \
#       -f docker-compose.host-ollama.yml --profile demo up -d guard-api demo-rag
#   (RATE_LIMIT is high because every call reaches guard-api from the proxy; the proxy limits each visitor.)
set -euo pipefail
cd "$(dirname "$0")/.."
CLOUDFLARED="${CLOUDFLARED:-cloudflared}"
GUARD_API_KEY="$(grep '^GUARD_API_KEY=' .env | cut -d= -f2-)"
export GUARD_API_KEY WEB_DIR=flutter_app/build/web
# The web app on GitHub Pages calls this proxy from another origin (D61).
export CORS_ORIGINS="${CORS_ORIGINS:-https://f243077-cell.github.io}"
if [ ! -f "$WEB_DIR/index.html" ] || ! grep -q '/guard' "$WEB_DIR/main.dart.js"; then
  (cd flutter_app && MSYS_NO_PATHCONV=1 flutter build web --release --dart-define=GUARD_URL=/guard --dart-define=DEMO_URL=/demo)
fi
curl -sf http://127.0.0.1:8001/health > /dev/null || { echo "guard-api is not running" >&2; exit 1; }
curl -sf http://127.0.0.1:8002/health > /dev/null || { echo "demo-rag is not running" >&2; exit 1; }
uvicorn deploy.proxy:app --host 127.0.0.1 --port 7860 --log-level warning &
trap 'kill %1 2>/dev/null' EXIT
sleep 3
# The public address is printed by the tunnel ("https://<random>.trycloudflare.com" or "...lhr.life").
# Cloudflare's quick tunnel is fast but its free API sometimes does not answer: retry, then fall back to
# localhost.run over SSH (also free and account-less, but throttled to a few KB/s, too slow for the 1st page load).
echo "Share: https://f243077-cell.github.io/Roman-Urdu-Guard-Model/?api=<the https address printed below>" >&2
for try in 1 2 3 4 5 6; do
  "$CLOUDFLARED" tunnel --no-autoupdate --edge-ip-version 4 --url http://127.0.0.1:7860 && exit 0
  echo "cloudflare quick tunnel failed (try $try); retrying in 20 s" >&2; sleep 20
done
ssh -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 -R 80:127.0.0.1:7860 nokey@localhost.run
