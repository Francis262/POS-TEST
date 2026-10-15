#!/usr/bin/env python3
"""Configure freshly generated Flutter Android files for the original POS app.

This script does not modify lib/main.dart or the application logic.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
manifest = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
if not manifest.is_file():
    raise SystemExit(f"AndroidManifest.xml manjka: {manifest}")

xml = manifest.read_text(encoding="utf-8")
if 'android.permission.CAMERA' not in xml:
    xml, count = re.subn(
        r"(<manifest\b[^>]*>)",
        r'\1\n    <uses-permission android:name="android.permission.CAMERA" />',
        xml,
        count=1,
        flags=re.DOTALL,
    )
    if count != 1:
        raise SystemExit("V AndroidManifest.xml ni značke <manifest>.")
xml, count = re.subn(
    r'(android:label=")[^"]+(")',
    r'\1POS Zaključek Izmene\2',
    xml,
    count=1,
)
if count != 1:
    raise SystemExit("Ni bilo mogoce najti android:label v AndroidManifest.xml.")
manifest.write_text(xml, encoding="utf-8")

gradle_kts = root / "android" / "app" / "build.gradle.kts"
gradle_groovy = root / "android" / "app" / "build.gradle"
gradle = gradle_kts if gradle_kts.exists() else gradle_groovy
if not gradle.exists():
    raise SystemExit("Manjka android/app/build.gradle(.kts).")

content = gradle.read_text(encoding="utf-8")
if gradle.suffix == ".kts":
    pattern = r"(?m)^(\s*)minSdk\s*=\s*(?:flutter\.minSdkVersion|\d+)\s*$"
    replacement = r"\g<1>minSdk = 24"
else:
    pattern = r"(?m)^(\s*)minSdkVersion\s+(?:flutter\.minSdkVersion|\d+)\s*$"
    replacement = r"\g<1>minSdkVersion 24"

content, count = re.subn(pattern, replacement, content, count=1)
if count != 1:
    raise SystemExit("Ni bilo mogoce nastaviti minSdk na 24.")
gradle.write_text(content, encoding="utf-8")
print("Android nastavljen: dovoljenje za kamero, ime aplikacije, minSdk 24.")
