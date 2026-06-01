# Acquisitions API

Express.js authentication API backed by PostgreSQL via [Neon](https://neon.tech), with Docker support for local development (Neon Local) and production (Neon Cloud).

## Architecture

| Environment | Database | Connection |
|-------------|----------|------------|
| **Development (Docker)** | Neon Local proxy | `postgres://neon:npg@neon-local:5432/neondb` |
| **Production** | Neon Cloud | `postgres://...@ep-xxx.neon.tech/neondb` |

The app uses `@neondatabase/serverless` + Drizzle ORM. When `NEON_LOCAL=true`, the database client is configured to route HTTP requests through the Neon Local proxy.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and Docker Compose v2
- [Node.js](https://nodejs.org/) 22+ (for running migrations on the host in production)
- A [Neon account](https://console.neon.tech) with:
  - **API key** ([manage keys](https://console.neon.tech/app/settings/api-keys))
  - **Project ID** (Project Settings → General)

## Environment files

| File | Purpose |
|------|---------|
| `.env.development.example` | Template for local Docker dev (copy to `.env.development`) |
| `.env.development` | Local Docker dev values (**gitignored**, create from example) |
| `.env.production.example` | Template for production secrets |
| `.env.production` | Real production values (**gitignored**, create locally or inject via deploy platform) |
| `.env.example` | Reference for all supported variables |

### How `DATABASE_URL` switches between dev and prod

**Development** (`.env.development`):

```env
NEON_LOCAL=true
NEON_FETCH_ENDPOINT=http://neon-local:5432/sql
DATABASE_URL=postgres://neon:npg@neon-local:5432/neondb?sslmode=require
```

**Production** (`.env.production` or platform secrets):

```env
NEON_LOCAL=false
DATABASE_URL=postgres://user:password@ep-xxx.region.aws.neon.tech/neondb?sslmode=require
```

Docker Compose loads the appropriate file per environment:

- `docker-compose.dev.yml` → `.env.development`
- `docker-compose.prod.yml` → `.env.production`

---

## Quick start

| Command | What it does |
|---------|--------------|
| `npm run docker:dev` | Runs `scripts/dev.sh` — starts Neon Local + app, migrates, streams logs |
| `npm run docker:dev:down` | Stops the development stack |
| `npm run docker:prod` | Runs `scripts/prod.sh` — starts prod app, waits for health, migrates |
| `npm run docker:prod:down` | Stops the production stack |

---

## Local development with Neon Local

Neon Local runs as a Docker sidecar. It creates an **ephemeral Neon branch** when the container starts and removes it when the container stops (unless you configure `DELETE_BRANCH=false`).

### 1. Configure Neon credentials

Create `.env.development` and set your Neon API credentials:

```env
NEON_API_KEY=your_neon_api_key
NEON_PROJECT_ID=your_neon_project_id
# Optional: PARENT_BRANCH_ID=br-xxx
```

### 2. Start the stack

```bash
npm run docker:dev
```

This runs `scripts/dev.sh`, which:

1. Verifies `.env.development` exists and Docker is running
2. Creates `.neon_local/` and adds it to `.gitignore`
3. Builds and starts containers in the background (`docker-compose.dev.yml`)
4. Waits for Neon Local and the app `/health` endpoint
5. Runs Drizzle migrations **inside the app container**
6. Streams container logs (Ctrl+C stops log watching; containers keep running)

This starts:

- **`neon-local`** — Neon Local proxy on port `5432`
- **`app`** — Express API on port `3000` with hot reload

### 3. Verify

```bash
curl http://localhost:3000/health
```

### 4. Stop

```bash
npm run docker:dev:down
# or
docker compose -f docker-compose.dev.yml down
```

### Manual fallback (without the script)

```bash
docker compose -f docker-compose.dev.yml up --build -d
docker compose -f docker-compose.dev.yml exec app npm run db:migrate
docker compose -f docker-compose.dev.yml logs -f
```

---

## Production with Neon Cloud

Production connects **directly to Neon Cloud**. There is no Neon Local container — Neon's serverless Postgres is hosted externally.

### 1. Create production env file

```bash
cp .env.production.example .env.production
```

Fill in real values:

```env
NODE_ENV=production
NEON_LOCAL=false
DATABASE_URL=postgres://user:password@ep-xxx.region.aws.neon.tech/neondb?sslmode=require
JWT_SECRET=<strong-random-secret>
ARCJET_KEY=<production-arcjet-key>
```

> **Never commit `.env.production`.** In CI/CD or cloud deploys, inject `DATABASE_URL`, `JWT_SECRET`, and `ARCJET_KEY` via your platform's secret manager instead.

### 2. Start production stack

```bash
npm run docker:prod
```

This runs `scripts/prod.sh`, which:

1. Verifies `.env.production` exists and Docker is running
2. Builds and starts the production container in detached mode
3. Waits for the app `/health` endpoint
4. Runs Drizzle migrations on the **host** using variables from `.env.production`

### 3. Verify

```bash
curl http://localhost:3000/health
```

### 4. View logs

```bash
docker logs -f acquisitions-app-prod
```

### 5. Stop

```bash
npm run docker:prod:down
# or
docker compose -f docker-compose.prod.yml down
```

### Manual fallback (without the script)

```bash
docker compose -f docker-compose.prod.yml up --build -d
set -a && source .env.production && set +a && npm run db:migrate
```

---

## Running without Docker

```bash
cp .env.example .env
# Set DATABASE_URL to your Neon Cloud connection string
npm install
npm run db:migrate
npm run dev
```

---

## Docker files

| File | Description |
|------|-------------|
| `Dockerfile` | Multi-stage build (`development` + `production` targets) |
| `docker-compose.dev.yml` | App + Neon Local for development |
| `docker-compose.prod.yml` | App only, connects to external Neon Cloud |
| `docker-entrypoint.sh` | Production container entrypoint |
| `scripts/dev.sh` | Dev startup: preflight, compose up, migrate, log stream |
| `scripts/prod.sh` | Prod startup: preflight, compose up, health wait, migrate |
| `.dockerignore` | Excludes dev artifacts from build context |

---

## Troubleshooting

**Application readiness check fails in scripts**

- Arcjet bot protection blocks default `curl` requests (403). `/health` is excluded from Arcjet so Docker and monitoring tools can probe it reliably.

**Neon Local readiness check fails**

- Neon Local returns HTTP `400` on `GET /` — that means it is running. The dev script checks for the `neon-local-proxy` server header, not a 2xx status.
- First startup can take 1–2 minutes while an ephemeral branch is created. Re-run `npm run docker:dev` or check logs: `docker compose -f docker-compose.dev.yml logs neon-local`

**App cannot connect to Neon Local**

- Confirm `NEON_LOCAL=true` and `NEON_FETCH_ENDPOINT=http://neon-local:5432/sql` in `.env.development`.
- Ensure the app service depends on `neon-local` and both are on the same Compose network.
- Verify `NEON_API_KEY` and `NEON_PROJECT_ID` are valid.

**Migrations fail in dev**

- Migrations must run **inside the app container** (not on the host) because `DATABASE_URL` uses the `neon-local` hostname.
- Ensure containers are running first: `docker compose -f docker-compose.dev.yml ps`

**Migrations fail in prod**

- Ensure `.env.production` has a valid Neon Cloud `DATABASE_URL`.
- The prod script loads `.env.production` before running `npm run db:migrate` on the host.

**Wrong application URL**

- The API runs on **port 3000**, not 5173.

**Container logs not found**

- Dev app container: `acquisitions-app-dev`
- Prod app container: `acquisitions-app-prod`

**JSON parse errors on API requests**

- Remove trailing commas from JSON bodies before sending.

**Ephemeral branch not created**

- Check Neon Local container logs: `docker compose -f docker-compose.dev.yml logs neon-local`
- Ensure your Neon project has a valid default branch or set `PARENT_BRANCH_ID`.

---

## License

