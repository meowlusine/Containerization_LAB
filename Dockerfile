# syntax=docker/dockerfile:1.7

# Frozen by the semester version manifest. Students may override this build
# argument only with another instructor-approved digest.
ARG PYTHON_IMAGE=python:3.12-slim@sha256:44ff437bba879d4941b710a369a8f19266aea34b29002807f0c487fabc9eec9b

# ---------- builder: hash-locked dependencies into a relocatable venv ----------
FROM ${PYTHON_IMAGE} AS builder
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1
WORKDIR /build
COPY requirements.txt ./
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --require-hashes --no-deps -r requirements.txt

# ---------- runtime: only the venv and the API files ----------
FROM ${PYTHON_IMAGE} AS runtime

ARG APP_VERSION=dev
ARG GIT_SHA=unknown
ARG SOURCE_URL=unknown

LABEL org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${GIT_SHA}"

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION="${APP_VERSION}" \
    GIT_SHA="${GIT_SHA}"

RUN groupadd --gid 10001 app \
 && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app

WORKDIR /srv/app
COPY --from=builder /opt/venv /opt/venv
COPY app ./app
COPY wsgi.py gunicorn.conf.py ./

USER 10001:10001

# The API listens on 8000. `docker stop` sends SIGTERM to Gunicorn (PID 1),
# which stops its workers gracefully (graceful_timeout=25 in gunicorn.conf.py).
EXPOSE 8000
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3)"]

CMD ["gunicorn", "-c", "gunicorn.conf.py", "wsgi:application"]
