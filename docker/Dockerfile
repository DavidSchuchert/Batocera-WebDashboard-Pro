# ── Build ──────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Runtime ─────────────────────────────────────────────
FROM python:3.11-slim

WORKDIR /app

# Security: non-root user
RUN useradd --create-home --shell /bin/bash appuser

COPY --from=builder /install /usr/local

COPY --chown=appuser:appuser server.py .
COPY --chown=appuser:appuser public/ ./public/

USER appuser
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

CMD ["python", "server.py"]
