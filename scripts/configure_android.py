#!/usr/bin/env python3
"""Configure generated Android build for the unchanged original POS Flutter app.

No modifications to lib/main.dart or to the Flutter application's behavior.
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
        raise SystemExit("V AndroidManifest.xml ni znacke <manifest>.")
xml, count = re.subn(
    r'(android:label=")[^"]+(")',
    r'\1POS Zaključek Izmene\2',
    xml,
    count=1,
)
if count != 1:
    raise SystemExit("Ni bilo mogoce nastaviti android:label.")
manifest.write_text(xml, encoding="utf-8")

gradle_kts = root / "android" / "app" / "build.gradle.kts"
gradle_groovy = root / "android" / "app" / "build.gradle"
gradle = gradle_kts if gradle_kts.exists() else gradle_groovy
if not gradle.is_file():
    raise SystemExit("Manjka android/app/build.gradle(.kts).")

content = gradle.read_text(encoding="utf-8")
if gradle.suffix == ".kts":
    min_pattern = r"(?m)^([ \t]*)minSdk\s*=\s*(?:flutter\.minSdkVersion|\d+)[ \t]*$"
    min_replacement = r"\g<1>minSdk = 24"
    ndk_pattern = r'(?m)^([ \t]*)ndkVersion\s*=\s*(?:flutter\.ndkVersion|"[^"]+")[ \t]*$'
    ndk_replacement = r'\g<1>ndkVersion = "27.0.12077973"'
    rule = 'proguardFiles("proguard-rules.pro")'
else:
    min_pattern = r"(?m)^([ \t]*)minSdkVersion\s+(?:flutter\.minSdkVersion|\d+)[ \t]*$"
    min_replacement = r"\g<1>minSdkVersion 24"
    ndk_pattern = r'''(?m)^([ \t]*)ndkVersion\s+(?:flutter\.ndkVersion|["'][^"']+["'])[ \t]*$'''
    ndk_replacement = r'\g<1>ndkVersion "27.0.12077973"'
    rule = "proguardFiles 'proguard-rules.pro'"

content, min_count = re.subn(min_pattern, min_replacement, content, count=1)
if min_count != 1:
    raise SystemExit("Ni bilo mogoce nastaviti minSdk na 24.")
content, ndk_count = re.subn(ndk_pattern, ndk_replacement, content, count=1)
if ndk_count != 1:
    raise SystemExit("Ni bilo mogoce nastaviti NDK 27.0.12077973.")

# Attach R8 rules only to the release build. Flutter 3.29's generated build
# contains a release { ... } block. Fail loudly if this changes.
if rule not in content:
    release_pattern = r"(?m)^([ \t]*)release\s*\{[ \t]*$"
    content, release_count = re.subn(
        release_pattern,
        lambda m: f"{m.group(0)}\n{m.group(1)}    {rule}",
        content,
        count=1,
    )
    if release_count != 1:
        raise SystemExit("Ni bilo mogoce dodati R8 pravil v release buildType.")
gradle.write_text(content, encoding="utf-8")

# The Flutter ML Kit plugin has references to optional non-Latin scripts.
# This app only requests TextRecognitionScript.latin; missing non-Latin
# recognizer classes are therefore intentionally optional.
rules = """# ML Kit optional recognizers not used by the original Latin-only POS app.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
"""
(root / "android" / "app" / "proguard-rules.pro").write_text(rules, encoding="utf-8")
print("Android nastavljen: kamera, ime, minSdk 24, NDK 27 in R8 ML Kit pravila.")
