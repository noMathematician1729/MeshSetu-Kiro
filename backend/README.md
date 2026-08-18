# MeshSetu control-room backend

Node/TypeScript replacement for the legacy FastAPI dashboard service.

```bash
cp .env.example .env
npm install
npm run build
npm start
```

The server listens on `0.0.0.0:8000`, serves the built React dashboard, exposes
the versioned `/v1` API, and preserves `/api/events` and `/ws` compatibility
routes. The gateway posts raw encrypted objects to `/v1/gateway/objects`; the
server validates the AES-256-GCM envelope, decodes `MeshEnvelope`, and only then
persists the SOS or verified voice evidence.

For the offline demo, run the repository root with Docker Compose:

```bash
docker compose up
```

Default local operator credentials are documented in `.env.example` and should
be replaced before a real deployment.
