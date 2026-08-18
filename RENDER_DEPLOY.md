# Render deployment

This repository is set up for a Render Blueprint via [`render.yaml`](./render.yaml).

Services created:

- `meshsetu-landing-page`: public Vite static site from `landing-page/`
- `meshsetu-admin-dashboard`: operator dashboard static site from `admin/client/`
- `meshsetu-control-room-backend`: Node/Express API + WebSocket service from `admin/server/`
- `meshsetu-backend-healthcheck`: Render cron job that hits the backend every 5 minutes
- `meshsetu-db`: Render Postgres for incident storage

## Before first sync

1. Push this repository to GitHub/GitLab.
2. In Render, create a new Blueprint and point it at the repo.
3. Before the first deploy completes, fill these secret env vars on `meshsetu-control-room-backend`:
   - `MESHSETU_ADMIN_PASSWORD`
   - `MESHSETU_GATEWAY_SECRET`
4. If you do not want free-tier services, change the `plan` values in [`render.yaml`](./render.yaml) before syncing.

## Runtime wiring

- The admin dashboard gets `VITE_API_BASE_URL` from the backend service's `RENDER_EXTERNAL_URL`.
- The backend allows browser requests from the admin dashboard URL via `MESHSETU_ADMIN_ORIGIN`.
- The backend health check path is `/health` and `/v1/health` remains available.
- The Render cron job runs every 5 minutes in UTC with schedule `*/5 * * * *`.

## Recommended post-deploy checks

1. Open the backend URL and confirm `/health` returns JSON.
2. Open the admin dashboard URL and sign in with your configured operator credentials.
3. Confirm dashboard login, live incident list loading, and WebSocket updates work.
4. Confirm the `meshsetu-backend-healthcheck` cron service shows successful runs in Render.
5. If the mobile gateway will call Render directly, set its gateway secret to the same `MESHSETU_GATEWAY_SECRET`.
