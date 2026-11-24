#!/bin/sh
# Warpdrive on Railway: derive the settings Railway can provide, migrate under a lock, then run
# the Next.js app, the WebSocket server, the background worker and the Caddy front in one
# container. If any of them stops, stop the rest and exit non-zero so Railway restarts us.
set -eu

fail() { echo "warpdrive: $*" >&2; exit 1; }

# --- public URLs (Railway's domain unless the deployer set their own) ---
if [ -z "${BASE_URL:-}" ]; then
  [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ] || fail "no public domain: generate a Railway domain or set BASE_URL"
  BASE_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
fi
BASE_URL="${BASE_URL%/}"
export BASE_URL
case "$BASE_URL" in
  https://*) WS_DEFAULT="wss://${BASE_URL#https://}/_ws" ;;
  *) WS_DEFAULT="ws://${BASE_URL#http://}/_ws" ;;
esac
export NEXT_PUBLIC_WS_URL="${NEXT_PUBLIC_WS_URL:-$WS_DEFAULT}"
export WS_PUBLIC_URL="${WS_PUBLIC_URL:-ws://127.0.0.1:8080}"

# --- sign-in: Google Workspace only. The Workspace domain defaults to the admin's domain ---
[ -n "${SEED_ADMIN_EMAIL:-}" ] || fail "SEED_ADMIN_EMAIL is required (your Google Workspace address)"
if [ -z "${GOOGLE_WORKSPACE_DOMAIN:-}" ]; then
  GOOGLE_WORKSPACE_DOMAIN="${SEED_ADMIN_EMAIL##*@}"
fi
export GOOGLE_WORKSPACE_DOMAIN
case "$GOOGLE_WORKSPACE_DOMAIN" in
  gmail.com|googlemail.com)
    echo "warpdrive: WARNING: sign-in needs a Google Workspace domain; personal @${GOOGLE_WORKSPACE_DOMAIN} accounts are rejected by Warpdrive" >&2 ;;
esac
[ -n "${GOOGLE_OAUTH_CLIENT_ID:-}" ] || fail "GOOGLE_OAUTH_CLIENT_ID is required"
[ -n "${GOOGLE_OAUTH_CLIENT_SECRET:-}" ] || fail "GOOGLE_OAUTH_CLIENT_SECRET is required"
export ALLOW_FIRST_LOGIN_ADMIN=false

# --- storage: a Railway Bucket (virtual-hosted style) by default ---
export S3_BUCKET="${S3_BUCKET:-warpdrive}"
export S3_FORCE_PATH_STYLE="${S3_FORCE_PATH_STYLE:-false}"
export MAX_FILE_BYTES="${MAX_FILE_BYTES:-26214400}"

# --- telemetry off unless the deployer opts in ---
export DISABLE_TELEMETRY="${DISABLE_TELEMETRY:-true}"

# --- memory: size each Node heap from the container limit (Free plan: 0.5 GB) ---
LIMIT_MB=1024
if [ -r /sys/fs/cgroup/memory.max ]; then
  m=$(cat /sys/fs/cgroup/memory.max)
  [ "$m" != max ] && LIMIT_MB=$((m / 1048576))
fi
[ "$LIMIT_MB" -gt 4096 ] && LIMIT_MB=4096
APP_HEAP=$((LIMIT_MB * 40 / 100)); WORKER_HEAP=$((LIMIT_MB * 20 / 100)); WS_HEAP=$((LIMIT_MB * 12 / 100))
[ "$WS_HEAP" -lt 48 ] && WS_HEAP=48
export UV_THREADPOOL_SIZE="${UV_THREADPOOL_SIZE:-2}"
echo "warpdrive: memory limit ${LIMIT_MB} MB (heaps: app ${APP_HEAP}, worker ${WORKER_HEAP}, ws ${WS_HEAP})"

# --- migrations (locked, so overlapping deploys never run them twice) ---
NODE_OPTIONS="--max-old-space-size=${WORKER_HEAP}" node migrate-locked.mjs || fail "migrations failed"

PIDS=""
start() { name=$1; shift; "$@" & PIDS="$PIDS $!"; echo "warpdrive: started $name (pid $!)"; }
stop_all() { for p in $PIDS; do kill "$p" 2>/dev/null || true; done; }
trap 'stop_all; exit 0' TERM INT

start ws env NODE_OPTIONS="--max-old-space-size=${WS_HEAP}" node dist/ws.mjs
start worker env NODE_OPTIONS="--max-old-space-size=${WORKER_HEAP}" node dist/worker.mjs
start app env PORT=3001 HOSTNAME=127.0.0.1 NODE_OPTIONS="--max-old-space-size=${APP_HEAP}" node_modules/.bin/next start -p 3001 -H 127.0.0.1
start caddy caddy run --config /etc/caddy/Caddyfile --adapter caddyfile

# BusyBox has no reliable `wait -n`, so poll the children.
while :; do
  for p in $PIDS; do
    if ! kill -0 "$p" 2>/dev/null; then
      echo "warpdrive: process $p stopped unexpectedly; restarting the container" >&2
      stop_all; sleep 1; exit 1
    fi
  done
  sleep 2
done
