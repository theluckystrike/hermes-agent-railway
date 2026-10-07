#!/usr/bin/env bash
# Smoke test for the Railway template image.
#
# Builds the repo Dockerfile (or uses $IMAGE), runs it with the template's
# environment and a named volume on /opt/data, then checks:
#   1. GET /health returns 200 with status ok
#   2. API calls without a key, or with a wrong key, return 401
#   3. the provider preset landed in /opt/data/config.yaml
#   4. a session created over the API survives `docker restart`
#   5. the same session survives a fresh container on the same volume (a redeploy)
#   6. TELEGRAM_BOT_TOKEN without TELEGRAM_ALLOWED_USERS stops the container
#
# Env knobs:
#   IMAGE=<ref>     skip the build and test this image
#   SMOKE_INIT=1    run with `docker run --init` so the entrypoint is not PID 1
#                   (the s6 fallback path some platforms trigger)
#   HOST_PORT=18642 local port for the API server
#   BOOT_TIMEOUT=240 seconds to wait for /health
set -euo pipefail

HOST_PORT="${HOST_PORT:-18642}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-240}"
RUN_ID="smoke-$$"
NAME="hermes-${RUN_ID}"
VOLUME="hermes-data-${RUN_ID}"
KEY="$(openssl rand -hex 32)"
BASE="http://127.0.0.1:${HOST_PORT}"
INIT_FLAG=()
[ "${SMOKE_INIT:-0}" = "1" ] && INIT_FLAG=(--init)

pass=0
fail=0
ok()   { pass=$((pass + 1)); printf 'PASS  %s\n' "$*"; }
bad()  { fail=$((fail + 1)); printf 'FAIL  %s\n' "$*"; }
info() { printf '....  %s\n' "$*"; }

cleanup() {
    docker rm -f "$NAME" "${NAME}-tg" >/dev/null 2>&1 || true
    docker volume rm -f "$VOLUME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [ -z "${IMAGE:-}" ]; then
    IMAGE="hermes-agent-railway:smoke"
    info "building $IMAGE from $(grep -m1 '^FROM' Dockerfile)"
    docker build -q -t "$IMAGE" . >/dev/null
fi
info "image $IMAGE (init=${SMOKE_INIT:-0})"

template_env=(
    -e PROVIDER=openrouter
    -e OPENROUTER_API_KEY=sk-or-smoke-placeholder
    -e API_SERVER_ENABLED=true
    -e API_SERVER_HOST=0.0.0.0
    -e "API_SERVER_KEY=${KEY}"
    -e PORT=8642
)

start() {
    docker run -d --name "$NAME" "${INIT_FLAG[@]}" \
        -v "${VOLUME}:/opt/data" -p "127.0.0.1:${HOST_PORT}:8642" \
        "${template_env[@]}" "$IMAGE" >/dev/null
}

code() { curl -s -o /dev/null -w '%{http_code}' "$@" || true; }

wait_health() {
    local t0=$SECONDS body
    while [ $((SECONDS - t0)) -lt "$BOOT_TIMEOUT" ]; do
        body="$(curl -fsS --max-time 3 "${BASE}/health" 2>/dev/null || true)"
        if printf '%s' "$body" | grep -q '"ok"'; then
            info "healthy after $((SECONDS - t0))s: $body"
            return 0
        fi
        if [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" != "true" ]; then
            info "container stopped while booting"
            docker logs --tail 40 "$NAME" 2>&1 | sed 's/^/      /'
            return 1
        fi
        sleep 2
    done
    docker logs --tail 40 "$NAME" 2>&1 | sed 's/^/      /'
    return 1
}

auth=(-H "Authorization: Bearer ${KEY}")

# ---- 1. health -------------------------------------------------------------
start
if wait_health; then ok "GET /health returns status ok"; else bad "GET /health did not return ok within ${BOOT_TIMEOUT}s"; exit 1; fi
c="$(code "${BASE}/health")"
[ "$c" = "200" ] && ok "GET /health is 200 without a key" || bad "GET /health returned $c"

# ---- 2. auth ---------------------------------------------------------------
c="$(code "${BASE}/v1/models")"
[ "$c" = "401" ] && ok "GET /v1/models without a key is 401" || bad "GET /v1/models without a key returned $c"
c="$(code -H 'Authorization: Bearer wrong-key-0000000000' "${BASE}/v1/models")"
[ "$c" = "401" ] && ok "GET /v1/models with a wrong key is 401" || bad "GET /v1/models with a wrong key returned $c"
c="$(code -X POST -H 'Content-Type: application/json' -d '{}' "${BASE}/api/sessions")"
[ "$c" = "401" ] && ok "POST /api/sessions without a key is 401" || bad "POST /api/sessions without a key returned $c"
c="$(code "${auth[@]}" "${BASE}/v1/models")"
[ "$c" = "200" ] && ok "GET /v1/models with the key is 200" || bad "GET /v1/models with the key returned $c"

# ---- 3. preset -------------------------------------------------------------
cfg="$(docker exec "$NAME" cat /opt/data/config.yaml 2>/dev/null || true)"
if printf '%s' "$cfg" | grep -Eq "default: ['\"]?anthropic/claude-haiku-4.5" && printf '%s' "$cfg" | grep -Eq "provider: ['\"]?openrouter"; then
    ok "config.yaml has provider openrouter and model anthropic/claude-haiku-4.5"
else
    bad "preset missing from config.yaml"
    printf '%s\n' "$cfg" | grep -nE '^model:|^  (default|provider|base_url):' | sed 's/^/      /'
fi

# ---- 4. session survives docker restart -----------------------------------
resp="$(curl -s "${auth[@]}" -H 'Content-Type: application/json' -X POST -d '{"title":"smoke-persist"}' "${BASE}/api/sessions")"
sid="$(printf '%s' "$resp" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for k in ("id","session_id"):
    if isinstance(d.get(k),str): print(d[k]); break
else:
    s=d.get("session") or {}
    print(s.get("id") or s.get("session_id") or "")' 2>/dev/null || true)"
if [ -n "$sid" ]; then ok "POST /api/sessions created session $sid"; else bad "POST /api/sessions response had no id: $resp"; exit 1; fi

docker restart "$NAME" >/dev/null
if wait_health; then ok "healthy again after docker restart"; else bad "not healthy after docker restart"; exit 1; fi
c="$(code "${auth[@]}" "${BASE}/api/sessions/${sid}")"
[ "$c" = "200" ] && ok "session $sid readable after docker restart" || bad "session $sid returned $c after docker restart"

# ---- 5. session survives a new container on the same volume ---------------
docker rm -f "$NAME" >/dev/null
start
if wait_health; then ok "fresh container on the same volume is healthy"; else bad "fresh container not healthy"; exit 1; fi
body="$(curl -s "${auth[@]}" "${BASE}/api/sessions/${sid}")"
if printf '%s' "$body" | grep -q "smoke-persist"; then
    ok "session $sid and its title survive a redeploy"
else
    bad "session $sid missing after redeploy: $body"
fi

# ---- 6. Telegram allowlist guard -------------------------------------------
docker run -d --name "${NAME}-tg" "${INIT_FLAG[@]}" \
    "${template_env[@]}" -e TELEGRAM_BOT_TOKEN=123456:smoke-placeholder "$IMAGE" >/dev/null
t0=$SECONDS
while [ "$(docker inspect -f '{{.State.Running}}' "${NAME}-tg")" = "true" ] && [ $((SECONDS - t0)) -lt 90 ]; do sleep 1; done
exit_code="$(docker inspect -f '{{.State.ExitCode}}' "${NAME}-tg")"
running="$(docker inspect -f '{{.State.Running}}' "${NAME}-tg")"
if [ "$running" = "false" ] && [ "$exit_code" != "0" ] && docker logs "${NAME}-tg" 2>&1 | grep -q "TELEGRAM_ALLOWED_USERS is empty"; then
    ok "Telegram token without allowlist stops the container (exit $exit_code)"
else
    bad "Telegram guard did not stop the container (running=$running exit=$exit_code)"
    docker logs --tail 20 "${NAME}-tg" 2>&1 | sed 's/^/      /'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
