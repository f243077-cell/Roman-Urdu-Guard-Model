# Hosted demo

## Always on: free Oracle Cloud VM (D62)

The whole backend runs on one Oracle Cloud **Always Free** VM; the web app stays on GitHub Pages. The link is fixed and the laptop can be off.

**Owner, once (about 30 minutes):**

1. Sign up at https://signup.cloud.oracle.com (free tier; a card is asked for identity checking only). Keep the account on **Always Free**: do not upgrade to Pay As You Go.
2. Compute, Instances, Create instance: image **Canonical Ubuntu 24.04**, shape **Ampere VM.Standard.A1.Flex** with **4 OCPU, 24 GB** (the Always Free limit). In "Add SSH keys" choose "Generate a key pair" and download the private key. If you see "Out of capacity", try another availability domain or later.
3. Networking, the instance's subnet, Default security list, Add ingress rules: source `0.0.0.0/0`, TCP, destination ports `80` and `443`.
4. Connect: `ssh -i <downloaded key> ubuntu@<public IP>` (or the console's Cloud Shell), then run
   `curl -fsSL https://raw.githubusercontent.com/f243077-cell/Roman-Urdu-Guard-Model/main/deploy/oracle/setup.sh | bash -s <public IP>`
   It installs Docker, downloads and checks the model, makes a new key in `~/ru-guard/.env`, starts everything and prints `Backend: https://<ip-with-dashes>.sslip.io` (20 to 40 minutes the first time).
5. GitHub repository, Settings, Secrets and variables, Actions, **Variables**: add `API_BASE` = that backend address. Then Actions, `pages`, Run workflow.

The demo is then https://f243077-cell.github.io/Roman-Urdu-Guard-Model/. To update after a code change, run the same command on the VM again. Oracle may reclaim an Always Free VM that stays idle for 7 days.

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

## Earlier design: one Hugging Face Space (D60, not available on this account)

One free Hugging Face Space (Docker, CPU basic: 2 vCPU, 16 GB) runs the whole demo in one container (decision D60):

```
browser ──https──> proxy :7860 (deploy/proxy.py) ──> guard-api :8001 ──> Ollama :11434 (ru-guard-1.5b-v2, qwen2.5:1.5b-instruct)
  (Flutter web,                 adds the API key        demo-rag  :8002 ──┘
   same origin)                 rate limits per visitor
```

## How the API key is kept secret

- The web app is built with `GUARD_URL=/guard` and `DEMO_URL=/demo` and **no key**; it calls its own origin, so there is no CORS and nothing secret in the JavaScript (checked: the key is in 0 files of the build).
- `deploy/start.sh` creates a new `GUARD_API_KEY` and `AUDIT_SALT` at every start. They exist only inside the container; guard-api and demo-rag listen on `127.0.0.1` only.
- The proxy adds the key to scans and drops any key a browser sends. It exposes only `/guard/health`, `/guard/v1/scan`, `/demo/health`, `/demo/chat`, `/demo/chat/stream` (no `/v1/stats`, no batch, no API docs).
- Limits per visitor (first `X-Forwarded-For` address): 30 scans and 6 chat questions a minute; at most 2 chat answers run at once (`SCANS_PER_MINUTE`, `CHATS_PER_MINUTE`, `CHAT_CONCURRENCY`). Requests over 64 KB are refused.

## Visitors do not see each other's work

The playground's history is kept in browser memory only (one tab, gone on reload). demo-rag answers each question on its own (no shared conversation). guard-api's audit log stores a keyed hash and the length, never the text; the database is in `/tmp` and is lost when the Space restarts. The only shared numbers, `/v1/stats`, are not reachable from outside.

## Create or update the Space

1. On huggingface.co: New Space, SDK **Docker**, template **Blank**, hardware **CPU basic (free)**, visibility Public.
2. Add the two files from `deploy/space/`: `Dockerfile` and `README.md` (its front matter sets `sdk: docker` and `app_port: 7860`).
3. The Space builds by itself (about 20 to 40 minutes: Flutter SDK, Python packages, Ollama, two 1 GB models). The Dockerfile clones this repository at `REF` (default `main`), so a code change reaches the Space with **Settings, Factory rebuild**.

No secrets need to be set in the Space settings.

## Limits of the free tier

CPU only: a scan takes about 1 s, a chat answer 30 to 90 s, and visitors queue. The Space sleeps after a period without visitors; the first visit after that waits for the start (a few minutes). Disk is not kept between restarts.

## Local check of the same setup

```bash
cd flutter_app && MSYS_NO_PATHCONV=1 flutter build web --release --dart-define=GUARD_URL=/guard --dart-define=DEMO_URL=/demo
cd .. && GUARD_API_KEY=<key of the local guard-api> WEB_DIR=flutter_app/build/web uvicorn deploy.proxy:app --port 7860
```

`MSYS_NO_PATHCONV=1` matters in Git Bash on Windows: without it `/guard` is rewritten to `C:/Program Files/Git/guard`. Checked on 2026-11-17 against the local stack: page loads with "Guard online", a Roman Urdu attack is blocked through `/guard/v1/scan` without a key from the browser, the chat stream arrives through `/demo/chat/stream`, `/guard/v1/stats` returns 404.
