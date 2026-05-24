# open-meet-docker

Run the entire **[open-meet](https://github.com/suraj-kashyap-dev/open-meet)** app
— the API, the user website, the admin console, and everything they depend on —
with **one command**, using only Docker.

You do **not** need to install Node, pnpm, PostgreSQL, Redis, or LiveKit on your
computer. If you can install Docker, you can run open-meet.

> This repo follows the same idea as `bagisto/bagisto-docker`: a small,
> self-contained folder that downloads the application and starts the whole
> thing in containers for you.

---

## 1. What you need first (prerequisites)

You only need two things installed:

1. **Docker Desktop** (includes Docker Compose) — https://docs.docker.com/get-docker/
   - After installing, **start Docker Desktop** and wait until it says it's running.
   - Check it works:
     ```bash
     docker --version
     docker compose version
     ```
     Both commands should print a version number.
2. **git** — https://git-scm.com/downloads
   - Check it works: `git --version`

That's it. Everything else is downloaded and run inside containers.

> **Ports:** the app uses ports `3000`, `3001`, `3002`, `5432`, `6379`,
> `7880–7882`, `8025`, `8080`, `1025`, `3478`, `5349`. If something else on your
> machine is already using them (for example, you're also running open-meet from
> source with its own `docker compose`), stop that first. See
> [Troubleshooting](#troubleshooting).

---

## 2. Run it (the quick start)

Open a terminal, go into this folder, and run the setup script:

```bash
cd open-meet-docker
./setup.sh
```

Then **wait**. The first run takes a while (it downloads the code, installs all
dependencies, and builds three apps). Later runs are much faster because Docker
caches the work.

When it's done, you'll see a summary with links. Open the user app in your
browser:

👉 **http://localhost:3000**

That's it — open-meet is running. 🎉

### What you can open

| What            | URL                          | Notes                                            |
| --------------- | ---------------------------- | ------------------------------------------------ |
| User app        | http://localhost:3000        | The main website — create an account and join meetings |
| Admin console   | http://localhost:3001        | Admin dashboard                                  |
| API             | http://localhost:3002/api    | Backend; API docs at http://localhost:3002/api/docs |
| Database viewer | http://localhost:8080        | Adminer — log in with the database details below |
| Email inbox     | http://localhost:8025        | MailHog — every email the app "sends" lands here |

### How to log in

- **Admin console** (http://localhost:3001): use the default admin account,
  created automatically the first time the app starts:
  - **Email:** `admin@example.com`
  - **Password:** `admin12345`
- **User app** (http://localhost:3000): click **Register** and create your own
  account. Any confirmation/verification emails show up in the
  **Email inbox** at http://localhost:8025 (nothing is sent to a real address).

> Want different admin credentials? Edit the `.env` file in this folder **before**
> the first run (see [Configuration](#configuration)).

---

## 3. What `./setup.sh` actually does

It's a normal shell script — here's each step in plain language:

1. **Checks Docker** is installed and running.
2. **Downloads the app** — clones the open-meet source code from GitHub into a
   `workspace/` folder inside this directory. (This is the "build context": the
   code Docker turns into an image.)
3. **Adds the build instructions** — copies the `Dockerfile` and a
   `.dockerignore` into that `workspace/` folder.
4. **Creates your settings file** — if there's no `.env` yet, it copies
   `.env.example` to `.env` so the app has secrets/passwords to use.
5. **Builds the image** (`docker compose build`) — installs all dependencies and
   compiles the API, the user app, and the admin app into one Docker image. This
   is the slow part on the first run.
6. **Starts everything** (`docker compose up -d --wait`) — launches the database,
   Redis, LiveKit (video), email catcher, and the three app containers, then
   waits until they report healthy.

After it starts, the API container automatically **sets up the database**
(runs migrations) and **creates the default admin** if one doesn't exist — so
there are no extra manual steps.

### Options you can pass

```bash
./setup.sh                 # download `main`, build, and run (the usual case)
./setup.sh -b some-branch  # build a specific branch / tag / commit instead
./setup.sh --skip-clone    # don't re-download; rebuild whatever is in workspace/
./setup.sh --no-cache      # rebuild from scratch, ignoring Docker's cache
./setup.sh --help          # show all options
```

---

## 4. Everyday commands

Run these from inside the `open-meet-docker` folder.

```bash
# See what's running and whether it's healthy
docker compose ps

# Watch the logs of one service (great for debugging). Ctrl+C to stop watching.
docker compose logs -f server     # the API
docker compose logs -f web        # the user app
docker compose logs -f admin      # the admin console

# Restart a single service
docker compose restart server

# Stop everything (your data is kept)
docker compose down

# Stop everything AND erase all data (fresh start: empty DB, no uploads)
docker compose down -v

# Start again after a `down` (no rebuild needed)
docker compose up -d

# Rebuild after the app code changed, then restart
docker compose build && docker compose up -d
```

**To get the latest open-meet code**, just run `./setup.sh` again — it pulls the
newest commit, rebuilds, and restarts.

---

## 5. Troubleshooting

**"port is already allocated" / "address already in use"**
Something else is using one of the ports. Most often it's open-meet running from
source (`pnpm dev`) or its own `docker compose`. Stop that, then retry. To see
what's using a port (e.g. 3000): `lsof -i :3000` (macOS/Linux).

**"Cannot connect to the Docker daemon"**
Docker isn't running. Open Docker Desktop and wait until it's started, then
re-run `./setup.sh`.

**The build is very slow / seems stuck**
The first build genuinely takes several minutes (it installs the whole project
and builds three apps). Watch progress with `docker compose logs -f` in another
terminal. Later builds are much faster.

**A page won't load right after setup**
The apps may still be starting. Check `docker compose ps` — wait until services
show `healthy`. If one says `unhealthy`, view its logs: `docker compose logs server`.

**I want to start completely fresh**
```bash
docker compose down -v          # remove containers + data
rm -rf workspace                # remove the downloaded code
./setup.sh                      # re-download, rebuild, run
```

---

## 6. Configuration

The `.env` file in this folder holds the secrets and passwords Docker passes to
the app (LiveKit keys, JWT secrets, the default admin login). `setup.sh` creates
it from `.env.example` on the first run. Edit it **before** your first
`./setup.sh` to change, for example, the admin email/password.

Everything else — ports, internal hostnames, and the URLs baked into the website
— lives in `docker-compose.yml` and the files under `config/`
(`livekit.yaml`, `egress.yaml`, `coturn.conf`).

If you need the front-end to talk to something other than `localhost` (for
example a LAN IP so others on your network can connect), change the
`build.args` (`NEXT_PUBLIC_*`) under the `server` service in
`docker-compose.yml`, then rebuild. Those values are compiled into the website
at build time.

---

## 7. How it works under the hood

For the curious — you don't need this to use the app.

- **One image, three apps.** A single multi-stage `Dockerfile` installs the
  pnpm/Turborepo workspace, generates the Prisma database client, and builds the
  server, web, and admin apps. `docker-compose.yml` then runs that **one** image
  as three services with different start commands. Only the `server` service
  declares the build; `web` and `admin` reuse the resulting `openmeet-app:local`
  image tag.
- **Browser URLs vs. internal URLs.** `NEXT_PUBLIC_*` values are compiled into
  the browser bundles and point at the published `localhost` ports. Server-side
  settings (`DATABASE_URL`, `REDIS_URL`, `LIVEKIT_HOST`, `SMTP_HOST`, …) use the
  internal Docker service names (`postgres`, `redis`, `livekit`, `mailhog`).
- **Database setup is automatic.** The server's entrypoint runs
  `prisma migrate deploy` (with retries) before starting, so the schema is
  always up to date; the API then creates the default admin if none exists.
- **Recordings.** LiveKit Egress and the API share the `uploads_data` volume
  (`/out` ↔ `apps/server/uploads`), so recorded files are saved by Egress and
  served back by the API.

### Folder layout

```
open-meet-docker/
  Dockerfile            # build instructions for the whole monorepo
  docker-compose.yml    # defines every service (infra + server/web/admin)
  setup.sh              # download → build → run
  .env / .env.example   # secrets/passwords for Docker
  config/               # livekit.yaml · egress.yaml · coturn.conf
  scripts/
    server-entrypoint.sh  # runs DB migrations, then starts the API
  workspace/            # the downloaded open-meet code (created by setup.sh)
```

---

## ⚠️ Not for production

These defaults exist to make local development easy: secrets are committed in
`.env`, LiveKit runs in `--dev` mode, the database viewer (Adminer) is open, and
all email goes to MailHog instead of real inboxes. **Do not deploy this as-is.**
Rotate every secret and harden each service before running anywhere public.
