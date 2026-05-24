# syntax=docker/dockerfile:1
#
# One image for the entire open-meet pnpm/Turborepo monorepo. The same built
# image runs all three apps (server, web, admin); docker-compose selects which
# one through `command` + `working_dir`.
#
# The base image is Debian (glibc) rather than Alpine on purpose: the project's
# native dependencies (argon2, sharp, the Prisma query engine) ship prebuilt
# glibc binaries, so a glibc base loads them directly and avoids a slow,
# fragile from-source rebuild against musl.

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

# python3/make/g++ are a safety net: if any native dependency lacks a prebuilt
# binary for this platform, node-gyp falls back to compiling it from source.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ git \
 && rm -rf /var/lib/apt/lists/*

# These NEXT_PUBLIC_* values are compiled into the browser bundles by
# `next build`, so they must be present as build-time args. They are the URLs
# the browser uses, hence the published localhost ports (not service names).
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

# The server's TypeScript build references the generated Prisma client's types,
# so the client must be generated before `turbo run build` compiles the server.
RUN pnpm --filter @open-meet/server exec prisma generate

# --concurrency=1 serializes the build. The two Next.js builds are memory-heavy
# and running them in parallel can exhaust RAM and get the build OOM-killed.
RUN pnpm exec turbo run build --concurrency=1

FROM base AS runtime
ENV NODE_ENV=production

# Carry the whole built workspace (compiled output, generated Prisma client, and
# every runtime dependency). This is larger than a pruned image but reliable:
# notably, next-intl reads its message JSON from the source tree at runtime, so
# those files must be present in the final image.
COPY --from=build /app /app

EXPOSE 3000 3001 3002

# docker-compose overrides this per service; the API is the sensible default.
WORKDIR /app/apps/server
CMD ["node", "dist/main.js"]
