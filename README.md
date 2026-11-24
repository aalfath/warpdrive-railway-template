[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/warpdrive?utm_medium=integration&utm_source=button&utm_campaign=warpdrive)

# Warpdrive on Railway

One-click [Railway](https://railway.com) template for [Warpdrive](https://github.com/sneg55/warpdrive), the open-source, self-hosted sales CRM and Pipedrive alternative (MIT).

**Version:** Warpdrive **2.14.5**, built from release commit [`1cfdd9ae`](https://github.com/sneg55/warpdrive/tree/1cfdd9ae2df5f45eb06ce88f59e77e940a2f3c04) on `node:24.22.3-alpine@sha256:116b800c…` (upstream publishes no Docker image). The `/_ws` front is `caddy:2.11.9-alpine@sha256:003a9780…`.

## What it deploys

| Service | What it does |
| --- | --- |
| **Warpdrive** (this repo) | The Next.js app on the public domain (health check `/api/health`), the realtime WebSocket server on `/_ws`, the pg-boss background worker and a small Caddy front, in one container. Migrations run on start under a Postgres advisory lock. If any process stops, the container exits non-zero so Railway restarts it. |
| **Postgres** | Railway Postgres on its own volume: all CRM data, sessions and jobs. |
| **Bucket** | A Railway Bucket for attachments, avatars and CSV imports (browser uploads use presigned URLs). |

It fits Railway's Free plan (one volume, one bucket, 0.5 GB per service): the Warpdrive service used about 300 MB in our test (browsing every page) and sizes its Node heaps from the container's memory limit.

## Before you deploy: Google Workspace sign-in

Warpdrive has **no password login**. Everyone signs in with Google, and the app accepts only accounts of **one Google Workspace domain**; personal `@gmail.com` accounts are rejected. You need:

1. A Google Workspace account, which becomes the first admin.
2. A Google OAuth client of type **Web application** in a Google Cloud project of your Workspace ([credentials page](https://console.cloud.google.com/apis/credentials)).

## Variables

| Variable | Set by | Meaning |
| --- | --- | --- |
| `SEED_ADMIN_EMAIL` | **you** | Your Google Workspace address. It becomes admin on its first sign-in, and sign-in is limited to its domain. |
| `GOOGLE_OAUTH_CLIENT_ID` | **you** | Client ID of the Web application OAuth client. |
| `GOOGLE_OAUTH_CLIENT_SECRET` | **you** | Its client secret. |
| `GOOGLE_WORKSPACE_DOMAIN` | optional | Only if your Workspace's primary domain differs from the admin email's domain. |
| `BASE_CURRENCY` | default `USD` | Three-letter currency code every amount is shown in. |
| `DATABASE_URL` | reference | `${{Postgres.DATABASE_URL}}` |
| `S3_*` | reference | The Railway Bucket's endpoint, bucket, region and keys. |
| `WS_TICKET_SECRET`, `TOKEN_ENCRYPTION_KEY`, `OAUTH_SIGNING_KEY` | generated | Secrets made by Railway at deploy time. Keep them stable: changing `TOKEN_ENCRYPTION_KEY` makes stored Gmail tokens unreadable. |
| `PORT` | `3000` | The port Railway routes to. |

The start script derives `BASE_URL` (`https://` + the Railway domain) and `NEXT_PUBLIC_WS_URL` (`wss://…/_ws`), and turns telemetry off. Set `BASE_URL` yourself if you add a custom domain.

## After deploy

Add both redirect URIs to your OAuth client, then open the Railway URL and sign in with the admin account:

```
https://YOUR-DOMAIN/auth/callback
https://YOUR-DOMAIN/api/gmail/oauth/callback
```

To use two-way Gmail, enable the Gmail API in the same Google Cloud project. Warpdrive's MCP server for AI assistants is at `https://YOUR-DOMAIN/api/mcp` (OAuth sign-in, user permissions apply); see [upstream's MCP guide](https://github.com/sneg55/warpdrive/blob/v2.14.5/docs-site/docs/features/mcp.md). Set `OAUTH_REGISTRATION=disabled` once your assistants are connected, or `MCP_ENABLED=false` to turn it off.

Left out on purpose: upstream's Garage storage service (replaced by a Railway Bucket so the stack fits the Free plan's single volume) and its TLS Caddy (Railway terminates TLS). Optional integrations (Intercom, X direct messages, PostHog) stay off until you set their variables from [upstream's list](https://github.com/sneg55/warpdrive/blob/v2.14.5/docs-site/docs/setup.md).

## Updates

Services built from this repo get Railway's "update available" notice when `main` changes. Each new Warpdrive version is one commit here (the commit pin in the `Dockerfile`) plus a [CHANGELOG](CHANGELOG.md) entry, with breaking changes listed first. Read it before you apply an update. Migrations run automatically on the next start.

## Files

- `Dockerfile`: downloads the pinned Warpdrive release commit, builds it like upstream's Dockerfile, and adds Caddy.
- `start.sh`: derives settings, runs migrations under a lock, and supervises the four processes.
- `migrate-locked.mjs`: waits for Postgres and runs upstream's migrations under an advisory lock.
- `Caddyfile`: routes `/_ws` to the WebSocket server and everything else to the app on `$PORT`.

The only change to upstream code: the S3 client's path-style addressing becomes a setting (`S3_FORCE_PATH_STYLE`, default `false` here), because Railway Buckets use virtual-hosted URLs.
