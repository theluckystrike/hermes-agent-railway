# Hermes Agent on Railway

A Railway template for [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research. It runs the official `nousresearch/hermes-agent:v2026.9.21` image, pinned by digest, with persistent state, a real healthcheck, an authenticated API and a mandatory Telegram allowlist.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/TEMPLATE_CODE?referralCode=&utm_medium=integration&utm_source=button&utm_campaign=hermes-agent-railway)

This template is community maintained. It is not an official Nous Research or Railway project. Hermes Agent itself is MIT licensed by Nous Research, and this repo adds only a start script and deploy config on top of the unmodified official image.

## What you get

| Item | Value |
|---|---|
| Image | `nousresearch/hermes-agent:v2026.9.21` pinned by multi-arch digest in `Dockerfile` |
| State | Railway volume on `/opt/data`, the image's own `HERMES_HOME` (config, `.env`, sessions, memories, skills, cron, logs) |
| Healthcheck | `GET /health` on the API server, 300 s timeout |
| Restart policy | `ON_FAILURE`, 10 retries |
| API | OpenAI compatible server on port 8642, every route except `/health` requires `Authorization: Bearer $API_SERVER_KEY` |
| Default model | `anthropic/claude-haiku-4.5` through OpenRouter, not the upstream default Opus |
| Telegram | Optional. The container refuses to start with a bot token and no allowlist |

The image entrypoint stays unchanged, so s6-overlay still bootstraps the volume as root, drops to the `hermes` user and supervises the gateway. The only addition is `railway/start.sh`, which validates the variables, writes the provider preset into `/opt/data/config.yaml` and runs `hermes gateway run`.

## Deploy

1. Click the button above and sign in to Railway.
2. Keep `PROVIDER=openrouter` and paste an `OPENROUTER_API_KEY`, or switch the preset (table below).
3. Optional Telegram. Create a bot with @BotFather, paste `TELEGRAM_BOT_TOKEN`, then put your numeric user ID in `TELEGRAM_ALLOWED_USERS` (message @userinfobot to get it).
4. Deploy. The first boot takes 1 to 3 minutes while the image is pulled and the volume is initialized. The deploy turns green once `/health` answers.
5. Copy `API_SERVER_KEY` from the service variables and test the API.

```sh
curl https://YOUR-DOMAIN.up.railway.app/health
curl https://YOUR-DOMAIN.up.railway.app/v1/chat/completions \
  -H "Authorization: Bearer $API_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"Say hi"}]}'
```

Any OpenAI compatible client (Open WebUI, LobeChat, the OpenAI SDKs) works with base URL `https://YOUR-DOMAIN.up.railway.app/v1` and the same key.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `PROVIDER` | `openrouter` | Provider preset. One of `openrouter`, `anthropic`, `openai`, `nous`, `custom` |
| `MODEL` | empty | Model ID. Empty picks the preset default below |
| `OPENROUTER_API_KEY` | empty | Key for `PROVIDER=openrouter` |
| `ANTHROPIC_API_KEY` | empty | Key for `PROVIDER=anthropic` |
| `OPENAI_API_KEY` | empty | Key for `PROVIDER=openai` (direct OpenAI API) |
| `NOUS_API_KEY` | empty | Key for `PROVIDER=nous`. Empty means device login (see below) |
| `API_SERVER_KEY` | generated, 64 hex chars | API bearer token. Under 16 characters stops the boot |
| `API_SERVER_ENABLED` | `true` | Turns on the API server and `/health`. Keep it on, the healthcheck needs it |
| `API_SERVER_HOST` | `0.0.0.0` | Bind address inside the container |
| `PORT` | `8642` | API port. Railway routes the domain and the healthcheck here |
| `TELEGRAM_BOT_TOKEN` | empty | Bot token from @BotFather |
| `TELEGRAM_ALLOWED_USERS` | empty | Numeric Telegram user IDs, comma separated. Mandatory when `TELEGRAM_BOT_TOKEN` is set |

Presets and their default models.

| `PROVIDER` | Hermes provider | Key variable | Default `MODEL` |
|---|---|---|---|
| `openrouter` | `openrouter` | `OPENROUTER_API_KEY` | `anthropic/claude-haiku-4.5` |
| `anthropic` | `anthropic` | `ANTHROPIC_API_KEY` | `claude-haiku-4-5-20251001` |
| `openai` | `openai-api` | `OPENAI_API_KEY` | `gpt-5.4-mini` |
| `nous` | `nous` | `NOUS_API_KEY` or device login | `anthropic/claude-haiku-4.5` |
| `custom` | untouched | any | untouched, configure with `hermes config set` over SSH |

Hermes sends a large system prompt with tool definitions on every turn. One public Railway deploy measured about 11,500 prompt tokens per message, so the model choice drives the bill. The upstream default is Claude Opus, while every preset here picks a Haiku or mini class model. Need more? Set `MODEL`.

The preset is written to `config.yaml` only when `PROVIDER`, `MODEL` or `PORT` change. A model picked by hand with `hermes model` over SSH stays in place across restarts.

Every other Hermes variable from the [upstream reference](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/reference/environment-variables.md) works too. Add it to the service variables and redeploy. Discord, Slack and the other platforms follow the same rule as Telegram and need their own `*_ALLOWED_USERS` list.

## Nous Portal sign in

With `PROVIDER=nous` and no `NOUS_API_KEY`, sign in once over Railway SSH with the device flow below, and the login lands in `/opt/data/auth.json` on the volume, where it survives every redeploy.

```sh
railway ssh
hermes auth add nous
```

## Telegram access control

A Telegram bot is public. Anyone who finds its username can message it, and every message spends model credits and can run tools. For that reason `railway/start.sh` stops the container when `TELEGRAM_BOT_TOKEN` is set and `TELEGRAM_ALLOWED_USERS` is empty or not numeric, and it refuses `TELEGRAM_ALLOW_ALL_USERS=true`. The deploy log names the missing variable.

## Upgrades

`Dockerfile` pins one release by tag and digest. A GitHub Action (`.github/workflows/bump.yml`) checks the latest Hermes release every day. When a new image is on Docker Hub, it pushes a bump branch, runs the smoke test on it, opens a PR and merges it on green. Railway then shows an update notice on every project deployed from this template, and you apply it from the dashboard when it suits you.

On boot, the official image runs Hermes config migrations against `/opt/data/config.yaml` and writes timestamped backups next to it first. Never run `hermes update` inside the container. The install tree is read only by design, so upgrades come only from a new image. To stay on a release, skip the update notice.

## Smoke test

`scripts/smoke.sh` runs the pinned image with the template variables and a named volume, then checks six things.

1. `GET /health` returns 200 with `{"status": "ok"}`.
2. `/v1/models` and `/api/sessions` return 401 without a key and with a wrong key.
3. The preset landed in `config.yaml`.
4. A session created through `POST /api/sessions` is still there after `docker restart`.
5. The same session is still there in a fresh container on the same volume, which is what a Railway redeploy does.
6. A bot token without an allowlist stops the container.

```sh
./scripts/smoke.sh                 # entrypoint as PID 1, the normal s6 path
SMOKE_INIT=1 ./scripts/smoke.sh    # docker run --init, the s6 fallback path
```

CI runs both modes on every push, every PR and every bump.

## Cost

Railway bills RAM, CPU and volume use. An idle Hermes gateway measured 200 to 300 MB of RAM in public Railway deploys, which is roughly 2 to 3 USD per month at Railway's list price of 10 USD per GB month, plus a small amount of CPU and volume. Model usage is billed by your provider, not by Railway.

## Security notes

1. The API server gives full tool access, including terminal commands, to anyone holding `API_SERVER_KEY`. Treat it like a root password and rotate it by editing the variable and redeploying.
2. The web dashboard is off. To use it, read the upstream [Docker guide](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/docker.md) on dashboard auth first. A public dashboard without auth was the entry point for real attacks in 2026.
3. Run one replica only. Two gateways on one data directory corrupt state, and Railway volumes already limit the service to one instance.

## Files

| Path | Role |
|---|---|
| `Dockerfile` | `FROM` the official image by tag and digest, adds the start script |
| `railway/start.sh` | Variable checks, provider preset, `hermes gateway run` |
| `railway.json` | Dockerfile build, `/health` healthcheck, restart policy |
| `template/variables.json` | Template variables, volume and domain port used when publishing |
| `scripts/smoke.sh` | Local and CI smoke test |
| `.github/workflows/smoke.yml` | Smoke test on push and PR |
| `.github/workflows/bump.yml` | Daily release check, bump PR, smoke, merge |

## License

MIT for this repo. Hermes Agent is MIT, copyright Nous Research.
