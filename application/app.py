import io
import os
import time
import uuid
import logging

import boto3
from flask import Flask, request, send_file, jsonify, render_template_string, redirect, url_for
from PIL import Image, ImageDraw, ImageFont
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Exposes /metrics: request counts by status/endpoint, latency histograms —
# this is what the PrometheusRule alerts (error rate, p95 latency) key off.
metrics = PrometheusMetrics(app)
metrics.info("watermark_app_info", "Watermark app build info", version="1.0.0")

# Path where the init container (or build) drops the watermark logo.
WATERMARK_PATH = os.environ.get("WATERMARK_PATH", "/app/assets/watermark.png")
WATERMARK_OPACITY = float(os.environ.get("WATERMARK_OPACITY", "0.7"))
WATERMARK_SCALE = float(os.environ.get("WATERMARK_SCALE", "0.4"))  # logo: % of base image width
WATERMARK_TEXT = os.environ.get("WATERMARK_TEXT", "Testing")       # bold text watermark
WATERMARK_TEXT_SCALE = float(os.environ.get("WATERMARK_TEXT_SCALE", "0.12"))  # text: % of width
S3_BUCKET = os.environ.get("WATERMARK_ASSETS_BUCKET", "")
S3_OUTPUT_PREFIX = os.environ.get("S3_OUTPUT_PREFIX", "outputs")
AWS_REGION = os.environ.get("AWS_REGION", "ap-south-1")

_s3 = boto3.client("s3", region_name=AWS_REGION) if S3_BUCKET else None


def apply_watermark(base_image: Image.Image, watermark_path: str) -> Image.Image:
    """Overlay a semi-transparent logo (bottom-right) plus a bold text
    watermark (bottom-centre)."""
    base = base_image.convert("RGBA")

    # ---- 1. Logo overlay (bottom-right) ----
    if os.path.exists(watermark_path):
        mark = Image.open(watermark_path).convert("RGBA")
        target_w = int(base.width * WATERMARK_SCALE)
        ratio = target_w / mark.width
        mark = mark.resize((target_w, int(mark.height * ratio)))

        alpha = mark.split()[3].point(lambda p: int(p * WATERMARK_OPACITY))
        mark.putalpha(alpha)

        position = (base.width - mark.width - 20, base.height - mark.height - 20)
        base.paste(mark, position, mark)

    # ---- 2. Bold text watermark (always drawn, bottom-centre) ----
    overlay = Image.new("RGBA", base.size, (255, 255, 255, 0))
    draw = ImageDraw.Draw(overlay)
    text = WATERMARK_TEXT
    # Big: font sized relative to image width
    font_size = max(24, int(base.width * WATERMARK_TEXT_SCALE))
    font = None
    for candidate in (
        "DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "LiberationSans-Bold.ttf",
    ):
        try:
            font = ImageFont.truetype(candidate, size=font_size)
            break
        except (IOError, OSError):
            continue
    if font is None:
        font = ImageFont.load_default()

    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (base.width - tw) // 2
    ty = base.height - th - int(base.height * 0.06)

    text_alpha = int(255 * WATERMARK_OPACITY)
    # Dark outline for contrast on light images
    outline = max(2, font_size // 20)
    for dx in (-outline, 0, outline):
        for dy in (-outline, 0, outline):
            if dx or dy:
                draw.text((tx + dx, ty + dy), text, font=font, fill=(0, 0, 0, text_alpha))
    draw.text((tx, ty), text, font=font, fill=(255, 255, 255, text_alpha))

    base = Image.alpha_composite(base, overlay)
    return base.convert("RGB")


@app.route("/healthz", methods=["GET"])
def healthz():
    return jsonify(status="ok"), 200


@app.route("/readyz", methods=["GET"])
def readyz():
    # Ready only once the watermark asset has been staged by the init container
    if os.path.exists(WATERMARK_PATH):
        return jsonify(status="ready"), 200
    return jsonify(status="waiting-for-watermark-asset"), 503


@app.route("/stress-cpu", methods=["GET"])
def stress_cpu():
    """Burns CPU for N seconds — for exercising the CPU/latency alerts
    during load testing. Not meant for production traffic."""
    seconds = min(float(request.args.get("seconds", 2)), 30)
    end = time.time() + seconds
    x = 0
    while time.time() < end:
        x += 1
    return jsonify(burned_seconds=seconds), 200


@app.route("/stress-mem", methods=["GET"])
def stress_mem():
    """Allocates ~N MB for a few seconds — for exercising the memory alert."""
    mb = min(int(request.args.get("mb", 150)), 500)
    seconds = min(float(request.args.get("seconds", 5)), 30)
    blob = bytearray(mb * 1024 * 1024)
    time.sleep(seconds)
    del blob
    return jsonify(allocated_mb=mb, held_seconds=seconds), 200


@app.route("/stress-fail", methods=["GET"])
def stress_fail():
    """Always returns 500 — for exercising the error-rate alert."""
    return jsonify(error="synthetic failure for alert testing"), 500


def upload_to_s3(image_bytes: bytes, key: str) -> str:
    """Store the watermarked image in S3 and return a presigned URL (valid 1h)."""
    _s3.put_object(
        Bucket=S3_BUCKET,
        Key=key,
        Body=image_bytes,
        ContentType="image/png",
    )
    return _s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": S3_BUCKET, "Key": key},
        ExpiresIn=3600,
    )


INDEX_HTML = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Watermark App</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 640px; margin: 3rem auto;
           padding: 0 1rem; color: #1a1a1a; }
    h1 { font-size: 1.6rem; }
    .card { border: 1px solid #e2e2e2; border-radius: 12px; padding: 1.5rem; margin-top: 1rem; }
    input[type=file] { margin: 1rem 0; display: block; }
    button { background: #2563eb; color: #fff; border: 0; border-radius: 8px;
             padding: 0.6rem 1.2rem; font-size: 1rem; cursor: pointer; }
    button:hover { background: #1d4ed8; }
    img { max-width: 100%; border-radius: 8px; margin-top: 1rem; }
    a.btn { display: inline-block; margin-top: 1rem; }
    .muted { color: #6b7280; font-size: 0.9rem; }
  </style>
</head>
<body>
  <h1>🖼️ Watermark App</h1>
  <p class="muted">Upload an image — it gets watermarked and stored in S3.</p>
  <div class="card">
    <form method="POST" action="/upload" enctype="multipart/form-data">
      <input type="file" name="image" accept="image/*" required>
      <button type="submit">Watermark &amp; upload</button>
    </form>
  </div>
  {% if result_url %}
  <div class="card">
    <strong>Done!</strong> Stored in S3 as <code>{{ s3_key }}</code>
    <img src="{{ result_url }}" alt="watermarked result">
    <a class="btn" href="{{ result_url }}" download>Download watermarked image</a>
  </div>
  {% endif %}
  {% if error %}
  <div class="card" style="border-color:#dc2626;color:#dc2626;">{{ error }}</div>
  {% endif %}
</body>
</html>
"""


@app.route("/", methods=["GET"])
def index():
    return render_template_string(INDEX_HTML), 200


@app.route("/upload", methods=["POST"])
def upload():
    """Browser form target: watermark the uploaded image, store in S3, show result."""
    if "image" not in request.files or request.files["image"].filename == "":
        return render_template_string(INDEX_HTML, error="Please choose an image."), 400

    file = request.files["image"]
    try:
        image = Image.open(file.stream)
    except Exception as exc:
        logger.warning("failed to open image: %s", exc)
        return render_template_string(INDEX_HTML, error="Invalid image file."), 400

    result = apply_watermark(image, WATERMARK_PATH)
    buf = io.BytesIO()
    result.save(buf, format="PNG")
    image_bytes = buf.getvalue()

    if not _s3:
        return render_template_string(
            INDEX_HTML, error="S3 is not configured (WATERMARK_ASSETS_BUCKET unset)."), 500

    key = f"{S3_OUTPUT_PREFIX}/{uuid.uuid4().hex}.png"
    try:
        result_url = upload_to_s3(image_bytes, key)
    except Exception as exc:
        logger.error("S3 upload failed: %s", exc)
        return render_template_string(INDEX_HTML, error=f"S3 upload failed: {exc}"), 500

    logger.info("watermarked image stored at s3://%s/%s", S3_BUCKET, key)
    return render_template_string(INDEX_HTML, result_url=result_url, s3_key=key), 200


@app.route("/watermark", methods=["POST"])
def watermark():
    if "image" not in request.files:
        return jsonify(error="missing 'image' file field"), 400

    file = request.files["image"]
    if file.filename == "":
        return jsonify(error="empty filename"), 400

    try:
        image = Image.open(file.stream)
    except Exception as exc:
        logger.warning("failed to open image: %s", exc)
        return jsonify(error="invalid image file"), 400

    result = apply_watermark(image, WATERMARK_PATH)

    buf = io.BytesIO()
    result.save(buf, format="PNG")
    buf.seek(0)
    return send_file(buf, mimetype="image/png", download_name="watermarked.png")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
