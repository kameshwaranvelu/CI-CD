import io
import os

from PIL import Image

import app as app_module


def test_healthz():
    client = app_module.app.test_client()
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_readyz_without_asset(tmp_path, monkeypatch):
    monkeypatch.setattr(app_module, "WATERMARK_PATH", str(tmp_path / "missing.png"))
    client = app_module.app.test_client()
    resp = client.get("/readyz")
    assert resp.status_code == 503


def test_watermark_missing_file():
    client = app_module.app.test_client()
    resp = client.post("/watermark")
    assert resp.status_code == 400


def test_watermark_applies_text_fallback(monkeypatch, tmp_path):
    # No watermark asset present -> falls back to text watermark, should not error
    monkeypatch.setattr(app_module, "WATERMARK_PATH", str(tmp_path / "missing.png"))

    img = Image.new("RGB", (200, 200), color=(120, 120, 120))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)

    client = app_module.app.test_client()
    resp = client.post(
        "/watermark",
        data={"image": (buf, "test.png")},
        content_type="multipart/form-data",
    )
    assert resp.status_code == 200
    assert resp.mimetype == "image/png"


def test_apply_watermark_returns_image():
    img = Image.new("RGB", (100, 100), color="white")
    result = app_module.apply_watermark(img, "/nonexistent/path.png")
    assert result.size == (100, 100)
    assert result.mode == "RGB"


def test_index_page():
    """Homepage returns the upload form."""
    client = app_module.app.test_client()
    resp = client.get("/")
    assert resp.status_code == 200
    assert b"Watermark" in resp.data


def test_upload_without_s3_configured(monkeypatch):
    """When no S3 bucket is set, /upload returns a friendly error, not a crash."""
    monkeypatch.setattr(app_module, "_s3", None)
    client = app_module.app.test_client()
    buf = io.BytesIO()
    Image.new("RGB", (50, 50), "red").save(buf, "PNG")
    buf.seek(0)
    resp = client.post(
        "/upload",
        data={"image": (buf, "test.png")},
        content_type="multipart/form-data",
    )
    assert resp.status_code == 500
    assert b"S3 is not configured" in resp.data


def test_upload_missing_file():
    """No file selected -> 400 with the form re-rendered."""
    client = app_module.app.test_client()
    resp = client.post("/upload")
    assert resp.status_code == 400
