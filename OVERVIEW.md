# Deploy and Host Warpdrive on Railway

Warpdrive is an open-source, self-hosted sales CRM and Pipedrive alternative (MIT). It gives a business-development team a drag-and-drop deal pipeline, a deal workspace with activities, notes, files and history, people and organizations with custom fields, two-way Gmail, roles and permissions, and live updates over WebSocket, all on your own server and database.

## About Hosting Warpdrive

This template runs Warpdrive 2.14.5, built from its release source, as one service that holds the Next.js app, the realtime WebSocket server, the background worker and a small Caddy front that routes `/_ws` to the WebSocket server. Railway Postgres stores the data and a Railway Bucket stores uploaded files. Migrations run on every start under a lock. Keys and secrets are generated. Warpdrive has no password login: everyone signs in with Google, and only accounts of one Google Workspace domain are accepted. So you need a Google Workspace account and a Google OAuth client before you deploy. Personal @gmail.com accounts can't sign in.

## Common Use Cases

* Run a sales or partnerships pipeline with deals, stages, activities and reminders
* Keep people, organizations and email threads in one CRM your team owns
* Move off Pipedrive with its CSV import, without per-seat pricing

## Dependencies for Warpdrive Hosting

* A Google Workspace domain and a Google OAuth client (Web application)
* PostgreSQL (Railway Postgres, included) and S3-compatible storage (Railway Bucket, included)

### Deployment Dependencies

* Warpdrive source and releases: https://github.com/sneg55/warpdrive (release v2.14.5)
* Warpdrive installation guide: https://github.com/sneg55/warpdrive/blob/v2.14.5/docs-site/docs/setup.md
* Google OAuth clients: https://console.cloud.google.com/apis/credentials
* Template source: https://github.com/aalfath/warpdrive-railway-template

### Implementation Details

Services in this template:

* **Warpdrive**: the app on the public domain (health check `/api/health`), plus the WebSocket server on `/_ws` and the pg-boss worker in the same container. If any of them stops, the container exits with an error and Railway restarts it.
* **Postgres**: Railway Postgres with its own volume. All CRM data, sessions and background jobs live here.
* **Bucket**: a Railway Bucket for attachments, avatars and CSV imports. Browsers upload to it with presigned URLs.

You answer three prompts:

* `SEED_ADMIN_EMAIL`: your Google Workspace address. It becomes the admin on its first sign-in. Sign-in is limited to its domain (set `GOOGLE_WORKSPACE_DOMAIN` if your Workspace's primary domain differs).
* `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET`: from a "Web application" OAuth client in Google Cloud, in the project that belongs to your Workspace.

After deploy, add these two authorized redirect URIs to the OAuth client, then open your Railway URL and sign in with the admin account:

```
https://YOUR-DOMAIN/auth/callback
https://YOUR-DOMAIN/api/gmail/oauth/callback
```

To use Gmail inside Warpdrive, also enable the Gmail API in that Google Cloud project. Other people from your domain who sign in become regular users. The MCP server for AI assistants is on at `/api/mcp` with OAuth sign-in. Telemetry is off.

It fits Railway's Free plan: the Warpdrive service used about 300 MB of its 0.5 GB in our test and sizes its Node heaps from the container limit. Updates: this template builds from a GitHub repo, so Railway shows an update notice when we release a new Warpdrive version. Read the repo's CHANGELOG before you apply it.

## Why Deploy Warpdrive on Railway?

<!-- Recommended: Keep this section as shown below -->
Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Warpdrive on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
<!-- End recommended section -->
