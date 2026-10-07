#!/bin/sh
# Railway start script for the official Hermes Agent image.
#
# The image entrypoint (s6-overlay /init, or the non-PID-1 fallback) runs the
# stage2 bootstrap as root first: it chowns /opt/data and seeds config.yaml.
# main-wrapper.sh then runs this script as the hermes user because the first
# CMD argument is an executable. Everything this script changes lives in
# /opt/data/config.yaml, so it reaches the s6-supervised gateway as well.
#
# Environment variables are the interface (Railway template variables):
#   PROVIDER                openrouter | anthropic | openai | nous (default openrouter)
#   MODEL                   model id; empty picks the preset's low-cost default
#   OPENROUTER_API_KEY / ANTHROPIC_API_KEY / OPENAI_API_KEY / NOUS_API_KEY
#   API_SERVER_KEY          required bearer token for the HTTP API
#   PORT                    API server port (Railway routes the domain here)
#   TELEGRAM_BOT_TOKEN      optional
#   TELEGRAM_ALLOWED_USERS  required when TELEGRAM_BOT_TOKEN is set
set -eu

log() { printf '[railway] %s\n' "$*" >&2; }
die() { printf '[railway] ERROR: %s\n' "$*" >&2; exit 64; }

# ---- API server: fail closed without a key --------------------------------
if [ "${API_SERVER_ENABLED:-false}" = "true" ]; then
    key="${API_SERVER_KEY:-}"
    [ -n "$key" ] || die "API_SERVER_KEY is empty. Set it to a long random value (the template generates one)."
    [ "${#key}" -ge 16 ] || die "API_SERVER_KEY is shorter than 16 characters."
fi

# ---- Telegram: the allowlist is mandatory ---------------------------------
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    case "$(printf '%s' "${TELEGRAM_ALLOW_ALL_USERS:-}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on) die "TELEGRAM_ALLOW_ALL_USERS lets any Telegram user spend your model credits. This template refuses it. Remove it and set TELEGRAM_ALLOWED_USERS." ;;
    esac
    allowed="$(printf '%s' "${TELEGRAM_ALLOWED_USERS:-}" | tr -d ' ')"
    [ -n "$allowed" ] || die "TELEGRAM_BOT_TOKEN is set but TELEGRAM_ALLOWED_USERS is empty. Add your numeric Telegram user ID (message @userinfobot to get it). Separate several IDs with commas."
    case "$allowed" in
        *[!0-9,]*) die "TELEGRAM_ALLOWED_USERS must be numeric user IDs separated by commas, got '$allowed'." ;;
    esac
fi

# ---- Provider preset -------------------------------------------------------
provider="$(printf '%s' "${PROVIDER:-openrouter}" | tr '[:upper:]' '[:lower:]')"
case "$provider" in
    openrouter) hermes_provider=openrouter; key_var=OPENROUTER_API_KEY; default_model="anthropic/claude-haiku-4.5" ;;
    anthropic)  hermes_provider=anthropic;  key_var=ANTHROPIC_API_KEY;  default_model="claude-haiku-4-5-20251001" ;;
    openai)     hermes_provider=openai-api; key_var=OPENAI_API_KEY;     default_model="gpt-5.4-mini" ;;
    nous)       hermes_provider=nous;       key_var=NOUS_API_KEY;       default_model="anthropic/claude-haiku-4.5" ;;
    custom)     hermes_provider=""; key_var=""; default_model="" ;;
    *) die "PROVIDER '$provider' is not one of openrouter, anthropic, openai, nous, custom." ;;
esac
model="${MODEL:-$default_model}"

if [ -n "$key_var" ]; then
    eval "key_value=\${$key_var:-}"
    if [ -z "$key_value" ]; then
        if [ "$provider" = "nous" ]; then
            log "NOUS_API_KEY is empty. Sign in once with 'railway ssh' then 'hermes auth add nous'. The login is stored on the /opt/data volume."
        else
            log "WARNING: PROVIDER=$provider but $key_var is empty. The gateway starts, but every model call fails until the key is set."
        fi
    fi
fi

# Write the preset into config.yaml only when it differs, so a manual
# 'hermes model' choice made over SSH survives restarts while PROVIDER and
# MODEL stay unchanged. PRESET_STAMP records the last applied preset.
stamp_file="${HERMES_HOME:-/opt/data}/.railway-preset"
want="$hermes_provider|$model|${PORT:-}"
have="$(cat "$stamp_file" 2>/dev/null || true)"
if [ "$provider" != "custom" ] && [ "$want" != "$have" ]; then
    log "applying preset provider=$hermes_provider model=$model"
    hermes config set model.provider "$hermes_provider" >/dev/null
    hermes config set model.default "$model" >/dev/null
    if [ "$hermes_provider" != "openrouter" ]; then
        # The seeded config points base_url at OpenRouter; other providers use their own endpoint.
        hermes config set model.base_url "" >/dev/null
    fi
    if [ -n "${PORT:-}" ]; then
        hermes config set gateway.api_server.port "$PORT" >/dev/null
    fi
    printf '%s' "$want" > "$stamp_file"
fi

if [ -n "${PORT:-}" ] && [ -z "${API_SERVER_PORT:-}" ]; then
    log "API server port follows PORT=$PORT"
fi

exec hermes gateway run "$@"
