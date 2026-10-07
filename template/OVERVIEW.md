# Deploy and Host Hermes Agent with Railway

Hermes Agent is the open source, self-improving AI agent from Nous Research. This template runs the official `nousresearch/hermes-agent` image, pinned to a tested release, with its state on a persistent volume, an authenticated OpenAI compatible API and optional Telegram access locked to an allowlist.

## About Hosting Hermes Agent

The template builds `FROM` the official image by tag and digest and adds one start script. The volume mounts on `/opt/data`, the image's own `HERMES_HOME`, so config, sessions, memories, skills and cron jobs survive every redeploy. Railway checks `GET /health` before it routes traffic.

Each API route except `/health` requires the generated `API_SERVER_KEY`. A daily CI job tests each new Hermes release (health, 401 without a key, sessions across restart and redeploy) and merges the bump, and Railway then offers the update to every deployed project.

## Common Use Cases

- A private Telegram assistant with long term memory, scheduled jobs and tools
- An OpenAI compatible backend for Open WebUI, LobeChat or your own scripts
- An always on research and automation agent with durable skills

## Dependencies for Hermes Agent Hosting

- One model provider key (OpenRouter, Anthropic, OpenAI or Nous Portal)
- Optional Telegram bot token from @BotFather plus your numeric Telegram user ID

### Deployment Dependencies

Hermes Agent source and docs live at https://github.com/NousResearch/hermes-agent. The template source, smoke test and upgrade history live at https://github.com/theluckystrike/hermes-agent-railway.

### Implementation Details

`PROVIDER` picks a preset with a low cost default model, `anthropic/claude-haiku-4.5` on OpenRouter for example, instead of the upstream default Opus. Set `MODEL` to override it. With `TELEGRAM_BOT_TOKEN` set and `TELEGRAM_ALLOWED_USERS` empty, the container stops with a clear log line, so a public bot never spends your credits.

```sh
curl https://YOUR-DOMAIN.up.railway.app/v1/models -H "Authorization: Bearer $API_SERVER_KEY"
```

This template is community maintained and is not an official Nous Research project.

## Why Deploy Hermes Agent on Railway?

Railway runs the container, the volume, TLS and restarts, so Hermes stays online without a VPS to patch. Logs, variables and SSH sit in one dashboard, and template updates arrive as a one click redeploy.
