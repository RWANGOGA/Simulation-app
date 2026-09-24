# Backend-fastapi Dockerfile
#
# Used by Crane Cloud (or any container host) to build and run the
# AtomyBridge Care API. Multi-stage build keeps the final image small
# and free of build tools.
#
# Build:    docker build -t atomybridge-api:latest .
# Run:      docker run -p 8000:8000 \
#               -e DATABASE_URL=postgresql+psycopg://atomy:atomy123@db:5432/atomybridge \
#               -e SECRET_KEY=... \
#               -e GROQ_API_KEY=... \
#               atomybridge-api:latest

# ── Stage 1: build wheels for any compiled deps ──────────────────────────
FROM python:3.11-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# System libs needed only to compile psycopg/psycopg2 wheels. They are
# NOT carried into the final image.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --prefix=/install -r requirements.txt

# ── Stage 2: slim runtime ───────────────────────────────────────────────
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=8000

# libpq is the only runtime C dependency (for psycopg/psycopg2). The rest
# of the image stays minimal.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Non-root user for Crane Cloud's hardened runtime.
RUN groupadd --system --gid 1001 atomy \
    && useradd --system --uid 1001 --gid atomy --no-create-home atomy

WORKDIR /app

# Copy installed packages and the application source. The entrypoint
# script lives at the repo root, so it goes in too.
COPY --from=builder /install /usr/local
COPY . /app

# Ensure the runtime user can read the app directory.
RUN chown -R atomy:atomy /app
USER atomy

EXPOSE 8000

# Crane Cloud sets $PORT. Honor it via a tiny Python shim that replaces
# the port token in argv and then execs uvicorn — works on the platform
# AND for `docker run -p ...:8000` locally. Invoked as `python ...` so
# the file does not need the executable bit (which the runtime user
# can't set after COPY restores root ownership).
COPY docker-entrypoint.py /app/docker-entrypoint.py

# CMD uses the JSON-array form so the shell never gets to interpret any
# of the tokens (e.g. `*` in --forwarded-allow-ips). If you change this
# line, keep it JSON-array only.
ENTRYPOINT ["python", "/app/docker-entrypoint.py"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "0.0.0.0/0"]
