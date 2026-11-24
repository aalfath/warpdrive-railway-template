# Changelog

Changes to this Railway template. Breaking changes come first in each entry.

## 2.14.5 (2026-11-24)

- First release: Warpdrive 2.14.5 (release commit `1cfdd9ae`) on Node 24.22.3 Alpine, with Railway Postgres and a Railway Bucket.
- One container runs the app, the WebSocket server (`/_ws`), the background worker and a Caddy front; any process stopping makes the container exit non-zero so Railway restarts it.
- Migrations run on start under a Postgres advisory lock.
- Upstream's path-style S3 addressing is now a setting (`S3_FORCE_PATH_STYLE`, default `false`) for Railway Buckets.
