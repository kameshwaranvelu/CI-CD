# ---------- Stage 1: build dependencies ----------
FROM python:3.12-slim AS builder

WORKDIR /build

# Build deps needed only to compile Pillow wheels
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libjpeg-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------- Stage 2: test ----------
# This stage runs the test suite during CI (docker build --target test)
# and never ships; it just fails the build if tests fail.
FROM builder AS test

COPY requirements-dev.txt .
RUN pip install --no-cache-dir -r requirements-dev.txt
COPY . .
RUN pytest --cov=app --cov-report=term-missing

# ---------- Stage 3: final runtime image ----------
FROM python:3.12-slim AS runtime

# Runtime image needs only the shared libs Pillow links against, not gcc
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg62-turbo \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

RUN addgroup --system --gid 10001 app && adduser --system --uid 10001 --ingroup app app

WORKDIR /app
COPY --from=builder /install /usr/local
COPY app.py .

# Watermark asset is populated at runtime by an init container into this dir
RUN mkdir -p /app/assets && chown -R app:app /app

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/healthz')" || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
