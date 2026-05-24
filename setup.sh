#!/usr/bin/env bash
# open-meet-docker bootstrap: clone open-meet into ./workspace, add the Dockerfile,
# build the shared image, and start the stack. Migrations and the default admin
# run automatically on server boot, so the app is ready when this finishes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

REPO_URL="https://github.com/suraj-kashyap-dev/open-meet.git"
WORKSPACE="$ROOT/workspace"
REF="main"
NO_CACHE=""
SKIP_CLONE=false

usage() {
  cat <<'EOF'
Usage: ./setup.sh [options]

  -b, --ref <branch|tag|sha>   open-meet ref to build (default: main)
      --no-cache               build images without the Docker layer cache
      --skip-clone             reuse the existing ./workspace checkout as-is
  -h, --help                   show this help

Examples:
  ./setup.sh                   # clone main, build, run
  ./setup.sh -b develop        # build a different branch
  ./setup.sh --skip-clone      # rebuild from the current ./workspace
EOF
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -b|--ref)     REF="${2:?--ref needs a value}"; shift 2 ;;
    --no-cache)   NO_CACHE="--no-cache"; shift ;;
    --skip-clone) SKIP_CLONE=true; shift ;;
    -h|--help)    usage 0 ;;
    *)            echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  echo "Error: docker compose is not available. Install Docker Compose." >&2
  exit 1
fi
echo "==> Using: $DC"

if ! docker info >/dev/null 2>&1; then
  echo "Error: can't reach the Docker daemon. Start Docker and retry." >&2
  exit 1
fi

if [ "$SKIP_CLONE" = true ]; then
  [ -d "$WORKSPACE/.git" ] || { echo "Error: --skip-clone but $WORKSPACE has no checkout." >&2; exit 1; }
  echo "==> Reusing existing checkout at workspace/ (--skip-clone)"
else
  if [ -d "$WORKSPACE/.git" ]; then
    echo "==> Refreshing workspace/ to $REF"
    git -C "$WORKSPACE" fetch --depth 1 origin "$REF"
    git -C "$WORKSPACE" checkout -f FETCH_HEAD
  else
    echo "==> Cloning $REPO_URL ($REF) into workspace/"
    rm -rf "$WORKSPACE"
    git clone --depth 1 --branch "$REF" "$REPO_URL" "$WORKSPACE" 2>/dev/null \
      || git clone --depth 1 "$REPO_URL" "$WORKSPACE"   # --branch rejects a sha; fall back to a plain clone
  fi
fi

# Build context is workspace/, so copy the Dockerfile + .dockerignore in on every
# run (kept out of the checkout, which stays a pristine mirror of open-meet).
cp "$ROOT/Dockerfile" "$WORKSPACE/Dockerfile"
cat > "$WORKSPACE/.dockerignore" <<'EOF'
.git
**/node_modules
**/.next
**/dist
**/.turbo
**/coverage
**/*.tsbuildinfo
**/.env
**/.env.local
**/.env.*.local
apps/server/uploads
EOF

if [ ! -f "$ROOT/.env" ]; then
  echo "==> Creating .env from .env.example"
  cp "$ROOT/.env.example" "$ROOT/.env"
fi

echo "==> Building the app image (this clones deps + builds 3 apps; first run is slow)"
$DC build $NO_CACHE

echo "==> Starting the full stack"
$DC up -d --wait --wait-timeout 240 --remove-orphans || {
  echo "Some services did not report healthy in time. Recent logs:" >&2
  $DC ps
  $DC logs --tail 40 server
  exit 1
}

cat <<EOF

============================================================
 open-meet is up 🎉
============================================================
  User app      http://localhost:3000
  Admin console http://localhost:3001
  API           http://localhost:3002/api   (Swagger: /api/docs)
  Adminer (DB)  http://localhost:8080        (postgres / postgres / openmeet)
  MailHog       http://localhost:8025

  Admin login   ${DEFAULT_ADMIN_EMAIL:-admin@example.com} / ${DEFAULT_ADMIN_PASSWORD:-admin12345}

  Logs   $DC logs -f server | web | admin
  Stop   $DC down          (add -v to wipe data volumes)
============================================================
EOF
