#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
unzip -oq LiteEdit_0.3_source_pack.zip -d "$ROOT"

# Fix a nullable Bitmap captured by a UI lambda and the no-op render fast path.
python3 - <<'PY'
from pathlib import Path
p=Path('app/src/main/java/com/liteedit/app/EditorActivity.kt')
s=p.read_text(encoding='utf-8')
old='''                rendered = ImageProcessor.render(
                    source,
                    snapshot,
                    PREVIEW_MAX_EDGE,
                    PREVIEW_MAX_PIXELS
                )

                runOnUiThread {
                    if (
                        isFinishing || isDestroyed ||
                        generation != renderGeneration
                    ) {
                        if (rendered !== source && rendered != null && !rendered.isRecycled) {
                            rendered.recycle()
                        }
                        return@runOnUiThread
                    }

                    imageView.setImageBitmap(rendered)
                    statusText.text = "Предпросмотр · ${rendered.width} × ${rendered.height}"
                }'''
new='''                rendered = ImageProcessor.render(source, snapshot, PREVIEW_MAX_EDGE, PREVIEW_MAX_PIXELS)
                val preview = rendered ?: return@execute
                runOnUiThread {
                    if (isFinishing || isDestroyed || generation != renderGeneration) {
                        if (preview !== source && !preview.isRecycled) preview.recycle()
                        return@runOnUiThread
                    }
                    imageView.setImageBitmap(preview)
                    statusText.text = "Предпросмотр · ${preview.width} × ${preview.height}"
                }'''
if old not in s: raise SystemExit('EditorActivity render block mismatch')
s=s.replace(old,new,1)
p.write_text(s,encoding='utf-8')
p=Path('app/src/main/java/com/liteedit/app/ImageProcessor.kt')
s=p.read_text(encoding='utf-8')
old='cropWidth == source.width && cropHeight == source.height'
if old not in s: raise SystemExit('ImageProcessor fast-path mismatch')
p.write_text(s.replace(old,'cropWidth == transformed.width && cropHeight == transformed.height',1),encoding='utf-8')
PY

mkdir -p app/src/main/res/layout app/src/main/res/values
cat > settings.gradle.kts <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "LiteEdit"
include(":app")
EOF
cat > build.gradle.kts <<'EOF'
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.21" apply false
}
EOF
cat > gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx3g -Dfile.encoding=UTF-8
org.gradle.caching=true
android.useAndroidX=true
kotlin.code.style=official
EOF
cat > app/build.gradle.kts <<'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.liteedit.app"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.liteedit.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 3
        versionName = "0.3.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildTypes {
        debug { isMinifyEnabled = false }
        release { isMinifyEnabled = false }
    }
}
EOF
cat > app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:allowBackup="false" android:label="@string/app_name"
        android:supportsRtl="true" android:theme="@android:style/Theme.Material.NoActionBar">
        <activity android:name=".EditorActivity" android:exported="false" />
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF
cat > app/src/main/res/values/strings.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources><string name="app_name">LiteEdit</string></resources>
EOF
cat > app/src/main/res/layout/activity_main.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:orientation="vertical" android:gravity="center" android:padding="28dp"
    android:background="#10110D">
    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
        android:text="LITEEDIT" android:textColor="#F0F0E8" android:textSize="30sp"
        android:textStyle="bold" android:letterSpacing="0.12" />
    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
        android:layout_marginTop="10dp" android:text="Простой редактор изображений"
        android:textColor="#9B9E8F" android:textSize="14sp" />
    <LinearLayout android:id="@+id/btnOpenImage" android:layout_width="match_parent"
        android:layout_height="58dp" android:layout_marginTop="42dp"
        android:background="#C9F36A" android:clickable="true" android:focusable="true"
        android:gravity="center" android:orientation="horizontal">
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:text="Выбрать изображение" android:textColor="#15170F"
            android:textSize="16sp" android:textStyle="bold" />
    </LinearLayout>
</LinearLayout>
EOF
