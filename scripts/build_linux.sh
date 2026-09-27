#!/usr/bin/env bash
# MediaShelf Linux 构建脚本（Ubuntu）
set -euo pipefail

cd "$(dirname "$0")/.."

# 中国镜像
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

echo "==> flutter pub get"
flutter --no-version-check --suppress-analytics pub get

# 禁用 Xiph 库（Opus/Ogg/Vorbis/FLAC）：本应用仅需 mp3/wav；
# 且 flutter_soloud 打包的 libopus 在 glibc 2.43 上编译，Ubuntu 24.04 仅 glibc 2.39，
# 禁用后彻底规避运行时加载报错。
export NO_XIPH_LIBS=1

echo "==> flutter build linux --release"
flutter --no-version-check --suppress-analytics build linux --release

echo ""
echo "✅ 构建完成：build/linux/x64/release/bundle/mediashelf"
