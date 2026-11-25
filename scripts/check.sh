#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export FLUTTER_SUPPRESS_ANALYTICS=true
flutter pub get
flutter analyze
flutter test
dart run tool/check.dart
