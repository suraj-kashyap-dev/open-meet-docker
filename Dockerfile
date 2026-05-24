# syntax=docker/dockerfile:1

# One image for the whole open-meet monorepo; compose runs it as server, web, and admin.
# Debian (glibc) base so prebuilt native deps (argon2, sharp, Prisma engine) load without a from-source rebuild.

ARG NODE_IMAGE=node:22-bookworm-slim

FROM ${NODE_IMAGE} AS base
ENV PNPM_HOME="/pnpm" \
    PATH="/pnpm:$PATH" \
    NEXT_TELEMETRY_DISABLED=1
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssl ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
RUN corepack enable
WORKDIR /app

FROM base AS build

# Toolchain so node-gyp can compile any native dep that lacks a prebuilt binary.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ git \
 && rm -rf /var/lib/apt/lists/*

# NEXT_PUBLIC_* are baked into the browser bundles at build time; use browser-reachable localhost ports.
ARG NEXT_PUBLIC_API_URL=http://localhost:3002
ARG NEXT_PUBLIC_WS_URL=http://localhost:3002
ARG NEXT_PUBLIC_LIVEKIT_URL=ws://localhost:7880
ARG NEXT_PUBLIC_WEB_URL=http://localhost:3000
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL \
    NEXT_PUBLIC_WS_URL=$NEXT_PUBLIC_WS_URL \
    NEXT_PUBLIC_LIVEKIT_URL=$NEXT_PUBLIC_LIVEKIT_URL \
    NEXT_PUBLIC_WEB_URL=$NEXT_PUBLIC_WEB_URL

COPY . .

RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store \
    pnpm install --frozen-lockfile

# Generate the Prisma client first; the server's TypeScript build depends on its types.
RUN pnpm --filter @open-meet/server exec prisma generate

# Serialize the build; parallel Next.js builds are memory-heavy and can get OOM-killed.
RUN pnpm exec turbo run build --concurrency=1

FROM base AS runtime
ENV NODE_ENV=production

# Copy the whole built workspace; next-intl reads its message JSON from the source tree at runtime.
COPY --from=build /app /app

EXPOSE 3000 3001 3002

# Default to the API; compose overrides command + working_dir per service.
WORKDIR /app/apps/server
CMD ["node", "dist/main.js"]
