#!/usr/bin/env python3
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ANDROID = ROOT / "android"
APP = ANDROID / "app"
SRC = Path(__file__).resolve().parent / "src"
RES = Path(__file__).resolve().parent / "res"

if not (APP / "build.gradle.kts").exists():
    raise SystemExit("android/app/build.gradle.kts is missing; run flutter create first")

# Copy native Kotlin sources after Flutter generates its scaffold.
native_src = SRC / "main" / "kotlin"
native_dst = APP / "src" / "main" / "kotlin"
if native_src.exists():
    shutil.copytree(native_src, native_dst, dirs_exist_ok=True)

# Install the supplied adaptive, maskable and monochrome Nexus launcher icons
# after Flutter creates the Android scaffold. Keeping these in the overlay
# makes CI builds reproducible without checking generated platform files in.
if RES.exists():
    shutil.copytree(RES, APP / "src" / "main" / "res", dirs_exist_ok=True)

# Patch Gradle with Firebase Messaging and Android Core-Telecom. Manual
# FirebaseOptions initialization means no google-services.json or Google
# Services Gradle plugin is required.
gradle_path = APP / "build.gradle.kts"
gradle = gradle_path.read_text()
marker = "flutter {\n"
deps = '''dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.core:core-telecom:1.0.0")
}

'''
if "com.google.firebase:firebase-messaging" not in gradle:
    if marker not in gradle:
        raise SystemExit("Could not find Flutter Gradle marker")
    gradle = gradle.replace(marker, deps + marker, 1)
elif "androidx.core:core-telecom" not in gradle:
    gradle = gradle.replace(
        '    implementation("androidx.core:core-ktx:1.17.0")\n',
        '    implementation("androidx.core:core-ktx:1.17.0")\n    implementation("androidx.core:core-telecom:1.0.0")\n',
        1,
    )
gradle_path.write_text(gradle)

manifest_path = APP / "src" / "main" / "AndroidManifest.xml"
ET.register_namespace("android", "http://schemas.android.com/apk/res/android")
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
tree = ET.parse(manifest_path)
root = tree.getroot()

permissions = [
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.USE_FULL_SCREEN_INTENT",
    "android.permission.RECORD_AUDIO",
    "android.permission.READ_CONTACTS",
    "android.permission.MODIFY_AUDIO_SETTINGS",
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.WAKE_LOCK",
    "android.permission.VIBRATE",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MICROPHONE",
    "android.permission.MANAGE_OWN_CALLS",
]
existing_permissions = {
    p.get(ANDROID_NS + "name") for p in root.findall("uses-permission")
}
for permission in permissions:
    if permission not in existing_permissions:
        node = ET.Element("uses-permission")
        node.set(ANDROID_NS + "name", permission)
        root.insert(0, node)

application = root.find("application")
if application is None:
    raise SystemExit("AndroidManifest application node missing")
application.set(ANDROID_NS + "icon", "@mipmap/ic_launcher")
application.set(ANDROID_NS + "roundIcon", "@mipmap/ic_launcher")
application.set(ANDROID_NS + "label", "Nexus One")

# Flutter's generated MainActivity is replaced by our overlay; make it able to
# receive fresh call intents while an existing instance is alive.
for activity in application.findall("activity"):
    name = activity.get(ANDROID_NS + "name") or ""
    if name.endswith("MainActivity"):
        activity.set(ANDROID_NS + "launchMode", "singleTop")
        activity.set(ANDROID_NS + "showWhenLocked", "true")
        activity.set(ANDROID_NS + "turnScreenOn", "true")

service_name = ".WhatomateMessagingService"
if not any(s.get(ANDROID_NS + "name") == service_name for s in application.findall("service")):
    service = ET.SubElement(application, "service")
    service.set(ANDROID_NS + "name", service_name)
    service.set(ANDROID_NS + "exported", "false")
    intent = ET.SubElement(service, "intent-filter")
    action = ET.SubElement(intent, "action")
    action.set(ANDROID_NS + "name", "com.google.firebase.MESSAGING_EVENT")

call_activity_name = ".IncomingCallActivity"
if not any(a.get(ANDROID_NS + "name") == call_activity_name for a in application.findall("activity")):
    activity = ET.SubElement(application, "activity")
    activity.set(ANDROID_NS + "name", call_activity_name)
    activity.set(ANDROID_NS + "exported", "false")
    activity.set(ANDROID_NS + "excludeFromRecents", "true")
    activity.set(ANDROID_NS + "showWhenLocked", "true")
    activity.set(ANDROID_NS + "turnScreenOn", "true")
    activity.set(ANDROID_NS + "theme", "@android:style/Theme.Material.NoActionBar")

tree.write(manifest_path, encoding="utf-8", xml_declaration=True)
print("Applied Whatomate Android native calling overlay")
