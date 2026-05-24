#!/bin/sh
# Apply migrations (idempotent), then start the API. The API creates the default
# admin on first boot when none exists.
set -e

cd /app/apps/server

echo "[entrypoint] applying database migrations (prisma migrate deploy)…"
n=0
until node_modules/.bin/prisma migrate deploy; do
  n=$((n + 1))
  if [ "$n" -ge 10 ]; then
    echo "[entrypoint] migrate deploy failed after $n attempts — giving up" >&2
    exit 1
  fi
  echo "[entrypoint] migrate failed (attempt $n) — retrying in 3s…"
  sleep 3
done

echo "[entrypoint] migrations applied — starting API…"
exec "$@"
