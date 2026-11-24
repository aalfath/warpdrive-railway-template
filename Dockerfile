# syntax=docker/dockerfile:1
# Warpdrive CRM for Railway: upstream sneg55/warpdrive v2.14.5 (MIT), built from its pinned
# release commit, because upstream publishes no Docker image. One container runs the Next.js
# app, the realtime WebSocket server, the pg-boss background worker and a small Caddy front
# that routes /_ws to the WebSocket server, so the whole app fits Railway's Free plan.

ARG NODE_IMAGE=node:24.22.3-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5

FROM caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0 AS caddy

# --- source: the release tag, checked against its commit ---
FROM ${NODE_IMAGE} AS src
ARG WARPDRIVE_VERSION=2.14.5
ARG WARPDRIVE_COMMIT=1cfdd9ae2df5f45eb06ce88f59e77e940a2f3c04
WORKDIR /app
RUN wget -qO- "https://codeload.github.com/sneg55/warpdrive/tar.gz/${WARPDRIVE_COMMIT}" | tar xz --strip-components=1 \
 && grep -q "\"version\": \"${WARPDRIVE_VERSION}\"" package.json \
 # Railway Buckets are virtual-hosted style; upstream hard-codes path style for Garage.
 && sed -i 's/forcePathStyle: true,/forcePathStyle: process.env.S3_FORCE_PATH_STYLE !== "false",/' \
      src/features/files/storage.ts src/features/files/storageRegion.ts \
 && grep -q S3_FORCE_PATH_STYLE src/features/files/storage.ts \
 && grep -q S3_FORCE_PATH_STYLE src/features/files/storageRegion.ts

FROM ${NODE_IMAGE} AS base
RUN corepack enable
WORKDIR /app

FROM base AS deps
COPY --from=src /app/package.json /app/pnpm-lock.yaml /app/pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

FROM base AS prod-deps
COPY --from=src /app/package.json /app/pnpm-lock.yaml /app/pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile --prod && rm -rf /root/.local/share/pnpm /root/.cache

FROM base AS build
COPY --from=deps /app/node_modules ./node_modules
COPY --from=src /app ./
# Next.js 16 starts one build worker per host CPU; cap it so the build fits small builders.
ENV CIRCLE_NODE_TOTAL=2 NEXT_TELEMETRY_DISABLED=1
# Placeholders only for `next build`, which imports the env schema (same as upstream's Dockerfile).
RUN NODE_ENV=production \
    DATABASE_URL=postgres://build:build@localhost:5432/build \
    GOOGLE_OAUTH_CLIENT_ID=build GOOGLE_OAUTH_CLIENT_SECRET=build \
    GOOGLE_WORKSPACE_DOMAIN=build.example.com BASE_URL=http://localhost:3000 \
    WS_TICKET_SECRET=build_placeholder_ws_ticket_secret_0123456789 \
    WS_PUBLIC_URL=ws://localhost:8080 S3_ENDPOINT=http://localhost:3900 \
    S3_ACCESS_KEY=build S3_SECRET_KEY=build \
    TOKEN_ENCRYPTION_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
    OAUTH_SIGNING_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
    SEED_ADMIN_EMAIL=build@example.com ALLOW_FIRST_LOGIN_ADMIN=false \
    pnpm build:docker

# --- runtime ---
FROM base AS runtime
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 APP_VERSION=2.14.5 \
    XDG_CONFIG_HOME=/tmp/caddy XDG_DATA_HOME=/tmp/caddy
COPY --from=caddy /usr/bin/caddy /usr/bin/caddy
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --chown=node:node --from=build /app/.next ./.next
COPY --from=build /app/public ./public
COPY --from=build /app/dist ./dist
COPY --from=build /app/drizzle ./drizzle
COPY --from=build /app/package.json /app/next.config.ts ./
COPY Caddyfile /etc/caddy/Caddyfile
COPY migrate-locked.mjs start.sh ./
RUN chmod 755 start.sh && PORT=3000 caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
USER 1000:1000
EXPOSE 3000
CMD ["/app/start.sh"]
