#!/usr/bin/env bash
# MediaShelf Android 构建脚本（需已安装 Android SDK + JDK 17+）
set -euo pipefail

cd "$(dirname "$0")/.."

# 中国镜像
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
# Android SDK（未在 shell 配置时也可独立构建）
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

echo "==> flutter pub get"
flutter --no-version-check --suppress-analytics pub get

echo "==> flutter build apk --release"
flutter --no-version-check --suppress-analytics build apk --release

echo ""
echo "✅ 构建完成：build/app/outputs/flutter-apk/app-release.apk"
