# Hosted demo

## Always on: a cloud VM with Azure for Students (D62, D64)

The whole backend runs on one Ubuntu VM; the web app stays on GitHub Pages. The link is fixed and the laptop can be off. Oracle's Always Free tier (D62) does not accept Pakistan, so the VM is on **Azure for Students**: $100 credit a year with a university email, no card.

**Owner, once (about 30 minutes):**

1. Sign up at https://azure.microsoft.com/free/students with the university email.
2. Portal, Create a resource, **Virtual machine**: subscription *Azure for Students*, new resource group `ru-guard`, a region the student policy allows (the closest one), image **Ubuntu Server 24.04 LTS (x64)**, size **Standard_B2s** (2 vCPU, 4 GB), authentication **SSH public key**, user `azureuser`, *Generate new key pair*. Public inbound ports: allow **SSH (22), HTTP (80), HTTPS (443)**. Review + create, then download the private key.
3. Connect: `ssh -i <downloaded key>.pem azureuser@<public IP>` (or the portal's *Connect, SSH using Azure CLI*), then run
   `curl -fsSL https://raw.githubusercontent.com/f243077-cell/Roman-Urdu-Guard-Model/main/deploy/vm/setup.sh | bash -s <public IP>`
   It adds a 4 GB swap file, installs Docker, downloads and checks the model, makes a new key in `~/ru-guard/.env`, starts everything and prints `Backend: https://<ip-with-dashes>.sslip.io` (20 to 40 minutes the first time).
4. GitHub repository, Settings, Secrets and variables, Actions, **Variables**: add `API_BASE` = that backend address. Then Actions, `pages`, Run workflow.

The demo is then https://f243077-cell.github.io/Roman-Urdu-Guard-Model/. To update after a code change, run the same command on the VM again.

**Credit:** a B2s VM with its disk and public IP uses most of the $100 in about 3 months (see *Cost Management* in the portal). Stopping (deallocating) the VM stops the compute charge; the credit renews each year while you are a student. When the credit ends, Azure stops the VM; nothing is charged to you.

## From the laptop: GitHub Pages plus a free tunnel (D61)

```
browser ──https──> GitHub Pages (Flutter web, no key)
   │
   └──https──> free tunnel ──> proxy :7860 on the laptop (deploy/proxy.py) ──> guard-api :8001, demo-rag :8002 (Docker) ──> Ollama
                               adds the key from .env, rate limits, CORS only for https://f243077-cell.github.io
```

On this Hugging Face account the Docker SDK is marked paid and CPU basic is not offered, so the Space below cannot run for free.

**One-time setup (owner):** GitHub repository, Settings, Pages, Source: **GitHub Actions**. Then Actions, `pages`, Run workflow (it also runs on each push that changes `flutter_app/`). The site is `https://f243077-cell.github.io/Roman-Urdu-Guard-Model/`.

**Each time you want the demo online:**

1. Start Ollama and the stack: `docker compose -f docker-compose.yml -f docker-compose.host-ollama.yml --profile demo up -d guard-api demo-rag`. Restart demo-rag after guard-api is healthy (`docker compose ... restart demo-rag`); its start-up ingest needs the guard, or every chunk is quarantined.
2. Run `bash deploy/public_from_laptop.sh`. It reads `GUARD_API_KEY` from `.env`, starts the proxy on `127.0.0.1:7860` and opens a tunnel. It prints the tunnel address, for example `https://abc.lhr.life`.
3. Share `https://f243077-cell.github.io/Roman-Urdu-Guard-Model/?api=https://abc.lhr.life`. The tunnel address itself also works (the proxy serves the same web build), but loads the 2.5 MB app through the tunnel.

The page accepts only `https://*.trycloudflare.com` and `https://*.lhr.life` in `?api=`. The demo stops when the script stops or the laptop sleeps, and the address changes at every start. The key stays in `.env` and in the proxy process.

## How the API key is kept secret

- The web app is built with `GUARD_URL=/guard` and `DEMO_URL=/demo` and **no key** (checked: the key is in 0 files of the build). It calls the backend from `API_BASE` or `?api=`.
- The key lives only in `.env` on the machine that runs the backend (on the Oracle VM, made by `deploy/vm/setup.sh`). guard-api, demo-rag and Ollama are not reachable from outside; only the proxy is (through Caddy or the tunnel).
- The proxy adds the key to scans and drops any key a browser sends. It exposes only `/guard/health`, `/guard/v1/scan`, `/demo/health`, `/demo/chat`, `/demo/chat/stream` (no `/v1/stats`, no batch, no API docs), and allows cross-origin calls only from `https://f243077-cell.github.io`.
- Limits per visitor (first `X-Forwarded-For` address): 30 scans and 6 chat questions a minute; at most 2 chat answers run at once (`SCANS_PER_MINUTE`, `CHATS_PER_MINUTE`, `CHAT_CONCURRENCY`). Requests over 64 KB are refused.

## Visitors do not see each other's work

The playground's history is kept in browser memory only (one tab, gone on reload). demo-rag answers each question on its own (no shared conversation). guard-api's audit log stores a keyed hash and the length, never the text. The only shared numbers, `/v1/stats`, are not reachable from outside.

## Speed

CPU only: a scan takes about 1 s, a chat answer 30 to 90 s, and visitors queue.

The Hugging Face Space of D60 was removed (its Docker hardware is paid on this account).

## Local check of the same setup

```bash
cd flutter_app && MSYS_NO_PATHCONV=1 flutter build web --release --dart-define=GUARD_URL=/guard --dart-define=DEMO_URL=/demo
cd .. && GUARD_API_KEY=<key of the local guard-api> WEB_DIR=flutter_app/build/web uvicorn deploy.proxy:app --port 7860
```

`MSYS_NO_PATHCONV=1` matters in Git Bash on Windows: without it `/guard` is rewritten to `C:/Program Files/Git/guard`. Checked on 2026-11-17 against the local stack: page loads with "Guard online", a Roman Urdu attack is blocked through `/guard/v1/scan` without a key from the browser, the chat stream arrives through `/demo/chat/stream`, `/guard/v1/stats` returns 404.
