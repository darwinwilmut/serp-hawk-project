# Changes Made for AWS Deployment

---

## Modified Files

### `main.py`

1. **Added S3 imports and config** (after existing imports, before `app = FastAPI(...)`):
   - Imported `boto3` and `ClientError` from `botocore.exceptions`
   - Added `S3_BUCKET` and `S3_REGION` variables read from environment

2. **Updated `FastAPI()` instantiation** — added `root_path="/api"` so FastAPI is aware of its public path prefix. This makes Swagger docs render correctly at `/api/docs` through nginx without touching any of the 104 route decorators.

3. **Added `/health` endpoint** — simple liveness probe returning `{"status": "ok"}`. Reachable at `https://yourdomain.com/api/health`.

4. **Updated CORS middleware** — changed `allow_origins` from wildcard `["*"]` to `[os.environ.get("FRONTEND_ORIGIN", "")]`. The allowed origin is now controlled via the `FRONTEND_ORIGIN` environment variable.

5. **Replaced `upload_file_to_server` function body** (~line 3454):
   - When `S3_BUCKET_NAME` env var is set: uploads file bytes to S3 via `boto3`, stores the full S3 URL (`https://<bucket>.s3.<region>.amazonaws.com/uploads/<filename>`) in the database.
   - When `S3_BUCKET_NAME` is not set (local development): falls back to writing to `static/uploads/` on disk.

---

### `requirements.txt`

- **Removed** `flask` — was listed as a dependency but never imported anywhere in the codebase.
- **Removed** `google-generativeai` — unused; document OCR uses OpenAI vision (GPT-4o), not Gemini.
- **Added** `boto3>=1.34.0` — AWS SDK for Python, required for S3 file uploads.

---

### `database.py`

- **Removed Neon PostgreSQL keepalive settings** from `connect_args` in the engine configuration:
  - Removed: `keepalives`, `keepalives_idle`, `keepalives_interval`, `keepalives_count`
  - Kept: `connect_timeout: 10`
  - Reason: These were workarounds for Neon's serverless cold-start latency. PostgreSQL now runs in Docker on the same internal network, so keepalives are unnecessary.

---

### `frontend/next.config.ts`

- **Added `output: 'standalone'`** to the Next.js config.
- Required for the frontend Docker image — standalone output produces a self-contained build (copies only the files needed to run `next start`) without requiring the full `node_modules` in the final image.

---

### `frontend/src/config.ts`

- **Removed the hardcoded Railway production URL** (`https://web-production-30b6.up.railway.app`).
- Production now falls back to an empty string if `NEXT_PUBLIC_API_BASE_URL` is not set, making it obvious when the env var is missing rather than silently calling the old Railway endpoint.

---

## New Files Added

### `Dockerfile`

Backend Docker image.
- Base: `python:3.11-slim` (Python 3.11 chosen over 3.13 for `psycopg2-binary` compatibility on Linux)
- Installs system deps (`gcc`, `libpq-dev`) required to build psycopg2
- Runs `uvicorn` with `--workers 1` — single worker is required because the WebSocket `ConnectionManager` holds connections in a Python dict; multiple workers would break message broadcasting

### `frontend/Dockerfile`

Frontend Docker image — two-stage build:
- **Stage 1 (builder)**: Installs all npm deps, accepts `NEXT_PUBLIC_API_BASE_URL` as a Docker build `ARG` and sets it as an `ENV` before running `npm run build`. This is required because `NEXT_PUBLIC_*` variables in Next.js are inlined into the JavaScript bundle at build time, not at runtime.
- **Stage 2 (runner)**: Copies only the `.next/standalone` output, static assets, and public folder. Results in a much smaller final image.

### `docker-compose.yml`

Orchestrates three services on the same internal Docker network (`crm`):

| Service | Image / Build | Port binding | Notes |
|---|---|---|---|
| `db` | `postgres:16-alpine` | Internal only | Named volume `pg_data` for data persistence; healthcheck gates backend startup |
| `backend` | Built from `Dockerfile` | `127.0.0.1:8000` | `DATABASE_URL` constructed from Postgres vars; reads `.env` for all other secrets |
| `frontend` | Built from `frontend/Dockerfile` | `127.0.0.1:3000` | `NEXT_PUBLIC_API_BASE_URL` passed as a build arg |

Both `backend` and `frontend` bind only to `127.0.0.1` — they are not reachable directly from the internet; all traffic must go through nginx.

### `nginx.conf`

Host-level nginx reverse proxy config. Key design decisions:

- **Single domain** (`yourdomain.com`) with path-based routing — no subdomains needed.
- **`/api/ws/` block comes before `/api/`** — nginx uses longest-prefix matching, so the more specific WebSocket block must appear first.
- **Trailing slash on `proxy_pass`** for the `/api/` block (`proxy_pass http://127.0.0.1:8000/`) — this strips the `/api` prefix before forwarding to FastAPI, so all existing route paths in `main.py` remain unchanged.
- **`proxy_read_timeout 86400`** on the WebSocket block — keeps WebSocket connections alive for up to 24 hours.
- **`client_max_body_size 25M`** — allows file uploads up to 25 MB.
- HTTP on port 80 redirects to HTTPS. ACME challenge path is exempted for Let's Encrypt certificate renewal.

### `.env.example`

Template listing every environment variable the application needs, with descriptions. Copy to `.env` on the EC2 instance and fill in real values before running `docker compose up`.
