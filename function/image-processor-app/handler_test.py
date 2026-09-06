"""
🧪 Automated Unit Testing Suite for Serverless Image Processor
Specification: Cloud-Native DevSecOps Unit & Security Verification
"""

import unittest
import json
import os
import sys
from PIL import Image

try:
    from .handler import validate_magic_bytes, validate_object_key, handle, strip_exif_metadata, _load_secret, ALLOWED_BUCKETS
except (ImportError, ValueError):
    # Fallback when run directly or discovered by unittest
    sys.path.insert(0, os.path.dirname(__file__))
    from handler import validate_magic_bytes, validate_object_key, handle, strip_exif_metadata, _load_secret, ALLOWED_BUCKETS

class TestImageProcessorSecurity(unittest.TestCase):

    def test_magic_bytes_valid_formats(self):
        """Test that legitimate image format magic bytes are correctly recognized."""
        png_header = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR'
        jpeg_header = b'\xff\xd8\xff\xe0\x00\x10JFIF'
        webp_header = b'RIFF\x00\x00\x00\x00WEBPVP8 '
        bmp_header = b'BM\x00\x00\x00\x00\x00\x00'

        self.assertEqual(validate_magic_bytes(png_header), "PNG")
        self.assertEqual(validate_magic_bytes(jpeg_header), "JPEG")
        self.assertEqual(validate_magic_bytes(webp_header), "WEBP")
        self.assertEqual(validate_magic_bytes(bmp_header), "BMP")

    def test_magic_bytes_malicious_script_rejection(self):
        """Test that disguised executable bash/PHP scripts are rejected."""
        fake_bash_script = b'#!/bin/bash\nrm -rf /'
        fake_php_script = b'<?php phpinfo(); ?>'
        random_garbage = b'\x00\x01\x02\x03\x04\x05'

        self.assertIsNone(validate_magic_bytes(fake_bash_script))
        self.assertIsNone(validate_magic_bytes(fake_php_script))
        self.assertIsNone(validate_magic_bytes(random_garbage))

    def test_path_traversal_validation(self):
        """🛡️ Test that path traversal and dangerous characters are rejected."""
        self.assertTrue(validate_object_key("sample_photo.jpg"))
        self.assertTrue(validate_object_key("2026/08/raw_input.png"))
        self.assertFalse(validate_object_key("../../etc/passwd"))
        self.assertFalse(validate_object_key("/root/id_rsa"))
        self.assertFalse(validate_object_key("image.png\x00.exe"))
        self.assertFalse(validate_object_key(""))

    def test_bucket_allowlist_enforcement(self):
        """🛡️ Test that unauthorized bucket access is rejected with HTTP 403."""
        class MaliciousBucketEvent:
            body = json.dumps({"bucket": "unauthorized-private-vault", "object": "stolen_data.png"})

        res = handle(MaliciousBucketEvent())
        self.assertEqual(res["statusCode"], 403)
        body = json.loads(res["body"])
        self.assertEqual(body["status"], "security_alert")

    def test_synthetic_benchmark_invocation(self):
        """Test that direct synthetic benchmark event returns valid FinOps telemetry."""
        class MockEvent:
            body = json.dumps({"benchmark_mode": "synthetic_test"})

        res = handle(MockEvent())
        self.assertEqual(res["statusCode"], 200)
        
        body = json.loads(res["body"])
        self.assertEqual(body["status"], "success")
        self.assertIn("telemetry", body)
        self.assertIn("execution_duration_ms", body["telemetry"])

    def test_exif_sanitization(self):
        """Test that EXIF metadata stripping creates a clean sanitized PIL image."""
        img = Image.new("RGB", (100, 100), color="blue")
        clean_img = strip_exif_metadata(img)
        self.assertEqual(clean_img.size, (100, 100))
        self.assertEqual(clean_img.mode, "RGB")

    def test_secret_loading_fallback(self):
        """Test that _load_secret falls back safely to default value."""
        val = _load_secret("CUSTOM_NONEXISTENT_VAR_123", default="safe_default")
        self.assertEqual(val, "safe_default")

    def test_secret_loading_required_exception(self):
        """Test that _load_secret raises ValueError if required and not present."""
        with self.assertRaises(ValueError):
            _load_secret("MANDATORY_SECRET_KEY_MISSING", default="", required=True)

    def test_tiff_bmp_magic_bytes(self):
        """Test that TIFF and BMP magic byte headers are recognized."""
        tiff_header = b'II*\x00\x08\x00\x00\x00'
        bmp_header = b'BM\x42\x00\x00\x00'
        self.assertEqual(validate_magic_bytes(tiff_header), "TIFF")
        self.assertEqual(validate_magic_bytes(bmp_header), "BMP")

    def test_unsupported_extension_rejection(self):
        """Test that non-image file extensions are safely rejected."""
        class InvalidExtEvent:
            body = json.dumps({"bucket": "uploads", "object": "malicious_script.sh"})
        res = handle(InvalidExtEvent())
        self.assertEqual(res["statusCode"], 400)

if __name__ == "__main__":
    unittest.main()
