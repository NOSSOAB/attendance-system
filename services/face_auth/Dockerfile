FROM python:3.11-slim-bookworm AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements-container.txt ./
RUN pip install --no-cache-dir -r requirements-container.txt \
    && pip install --no-cache-dir --no-deps mediapipe==0.10.14 \
    && pip install --no-cache-dir easydict==1.13 tqdm==4.67.1 cython==3.0.11 prettytable==3.12.0 scikit-learn==1.5.2 \
    && pip install --no-cache-dir --no-deps albumentations==1.4.0 insightface==0.7.3
RUN pip install --no-cache-dir --no-deps qudida==0.0.4

# Keep the recognition model out of Git while making the container self-contained.
COPY scripts/fetch_models.py /tmp/fetch_models.py
RUN python /tmp/fetch_models.py --models-dir /opt/face-models

FROM python:3.11-slim-bookworm AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    HOME=/home/faceauth \
    MPLCONFIGDIR=/tmp/matplotlib

RUN apt-get update \
    && apt-get install -y --no-install-recommends libgl1 libgles2 libegl1 libglib2.0-0 libgomp1 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 faceauth \
    && useradd --uid 10001 --gid 10001 --create-home --shell /usr/sbin/nologin faceauth

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app

COPY --chown=10001:10001 backend ./backend
COPY --chown=10001:10001 modules ./modules
COPY --chown=10001:10001 config.yaml ./config.yaml
COPY --chown=10001:10001 models/face_landmarker.task ./models/face_landmarker.task
COPY --from=builder --chown=10001:10001 /opt/face-models/w600k_r50.onnx ./models/w600k_r50.onnx

RUN mkdir -p /app/logs /app/outputs /app/models /app/database_faces /data /home/faceauth/.insightface \
    && chown -R 10001:10001 /app /data /home/faceauth

USER 10001:10001

EXPOSE 8000
CMD ["python", "-m", "uvicorn", "backend.app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
