# Open-Meet Docker

Run the entire **[Open-Meet](https://github.com/suraj-kashyap-dev/open-meet)** app — API, user website, admin console, and all its dependencies — with a **single command**, using only Docker. No need to install Node, pnpm, PostgreSQL, Redis, or LiveKit locally.

> ⚠️ **Local development only — not for production.** Secrets are committed, LiveKit runs in `--dev` mode, Adminer is open, and email goes to MailHog. Rotate every secret and harden each service before deploying anywhere public.

## Prerequisites

- **Docker Desktop** (includes Compose) — verify with `docker --version` and `docker compose version`.
- **git** — verify with `git --version`.

Make sure Docker is running before you start.

> **Ports used:** `3000`, `3001`, `3002`, `5432`, `6379`, `7880–7882`, `8025`, `8080`, `1025`, `3478`, `5349`. If another process (e.g. Open-Meet running from source) holds any of these, stop it first.

## Quick start

```bash
cd open-meet-docker
./setup.sh
```

The first run is slow (it downloads the code, installs dependencies, and builds three apps); later runs are cached. When it finishes, open **http://localhost:3000**.

### URLs

| What            | URL                          | Notes                                          |
| --------------- | ---------------------------- | ---------------------------------------------- |
| User app        | http://localhost:3000        | Main website — register and join meetings      |
| Admin console   | http://localhost:3001        | Admin dashboard                                |
| API             | http://localhost:3002/api    | Backend; docs at `/api/docs`                   |
| Database viewer | http://localhost:8080        | Adminer (`postgres` / `postgres` / `openmeet`) |
| Email inbox     | http://localhost:8025        | MailHog — captures every email the app sends   |

### Logins

- **Admin console** — default account created on first boot: `admin@example.com` / `admin12345`.
- **User app** — click **Register** to create an account; verification emails appear in MailHog (http://localhost:8025).

> To change the admin credentials, edit `.env` **before** the first `./setup.sh` run.

## `./setup.sh` options

```bash
./setup.sh                 # clone `main`, build, and run (default)
./setup.sh -b some-branch  # build a specific branch / tag / commit
./setup.sh --skip-clone    # reuse the existing workspace/ checkout
./setup.sh --no-cache      # rebuild ignoring the Docker cache
./setup.sh --help          # show all options
```

It checks Docker, clones Open-Meet into `workspace/`, copies in the `Dockerfile` + `.dockerignore`, creates `.env` from `.env.example` if missing, builds the image, and starts the stack. The server then runs migrations and creates the default admin automatically.

## Everyday commands

Run these from the `open-meet-docker` folder:

```bash
docker compose ps                    # status / health
docker compose logs -f server        # tail one service's logs (web | admin | livekit | …)
docker compose restart server        # restart one service
docker compose down                  # stop everything (data kept)
docker compose down -v               # stop and erase all data
docker compose up -d                 # start again after a down (no rebuild)
docker compose build && docker compose up -d   # rebuild after code changes
```

To pull the latest Open-Meet code, just run `./setup.sh` again.

## Configuration

- `.env` holds secrets Docker passes to the app (LiveKit keys, JWT secrets, admin login). Created from `.env.example` on first run; edit it **before** the first `./setup.sh`.
- Ports, internal hostnames, and the URLs baked into the website live in `docker-compose.yml` and `config/` (`livekit.yaml`, `egress.yaml`, `coturn.conf`).
- To reach the frontend from another machine (e.g. a LAN IP), change the `NEXT_PUBLIC_*` `build.args` under the `server` service in `docker-compose.yml`, then rebuild — those values are compiled into the website at build time.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `port is already allocated` | Another process holds a port — often Open-Meet from source. Stop it (`lsof -i :3000` to find it), then retry. |
| `Cannot connect to the Docker daemon` | Docker isn't running. Start Docker Desktop and re-run `./setup.sh`. |
| Build seems stuck | The first build takes several minutes. Watch `docker compose logs -f`. |
| A page won't load after setup | Apps may still be starting. Check `docker compose ps`; for an `unhealthy` service run `docker compose logs <service>`. |
| Want a clean slate | `docker compose down -v && rm -rf workspace && ./setup.sh` |

## How it works

- **One image, three apps.** A multi-stage `Dockerfile` builds the pnpm/Turborepo workspace once; `docker-compose.yml` runs that single `openmeet-app:local` image as `server`, `web`, and `admin` with different start commands.
- **Browser vs. internal URLs.** `NEXT_PUBLIC_*` values are compiled into the browser bundles and point at `localhost` ports; server-side settings (`DATABASE_URL`, `REDIS_URL`, `LIVEKIT_HOST`, `SMTP_HOST`, …) use internal Docker service names.
- **Automatic DB setup.** The server entrypoint runs `prisma migrate deploy` (with retries) before starting, then the API creates the default admin if none exists.
- **Recordings.** LiveKit Egress and the API share the `uploads_data` volume (`/out` ↔ `apps/server/uploads`), so recorded files are written by Egress and served by the API.

### Folder layout

```
open-meet-docker/
  Dockerfile            # build instructions for the whole monorepo
  docker-compose.yml    # every service (infra + server/web/admin)
  setup.sh              # download → build → run
  .env / .env.example   # secrets passed to Docker
  config/               # livekit.yaml · egress.yaml · coturn.conf
  scripts/
    server-entrypoint.sh  # runs DB migrations, then starts the API
  workspace/            # the downloaded Open-Meet code (created by setup.sh)
```
