#!/bin/bash
# Сборка RUTprompter.app.  Использование:
#   ./build.sh            — собрать в build/RUTprompter.app
#   ./build.sh run        — собрать и запустить
#   ./build.sh install    — собрать, положить в /Applications и запустить
#   ./build.sh check      — только самопроверка логики (CoreChecks)
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
  echo "Нет Swift. Установите инструменты разработчика: xcode-select --install"
  exit 1
fi

if [ "${1:-}" = "check" ]; then
  swift run -c debug CoreChecks
  exit 0
fi

echo "→ Компиляция (release)…"
swift build -c release --product RUTprompter
BIN="$(swift build -c release --show-bin-path)/RUTprompter"

APP="build/RUTprompter.app"
echo "→ Упаковка $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RUTprompter"
cp Support/Info.plist "$APP/Contents/Info.plist"

if [ -f Support/AppIcon-1024.png ]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Support/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d Support/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Подпись ad-hoc: без неё macOS не покажет запрос доступа к микрофону
# и распознаванию речи.
codesign --force --sign - "$APP"
echo "✓ Готово: $APP"

case "${1:-}" in
  run)
    pkill -x RUTprompter 2>/dev/null || true
    # Ждём, пока старая копия закроется, иначе open вернёт ошибку -600.
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x RUTprompter >/dev/null || break; sleep 0.3; done; sleep 0.7
    open "$APP"
    ;;
  install)
    pkill -x RUTprompter 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x RUTprompter >/dev/null || break; sleep 0.3; done; sleep 0.7
    rm -rf /Applications/RUTprompter.app
    cp -R "$APP" /Applications/
    open /Applications/RUTprompter.app
    echo "✓ Установлено в /Applications и запущено"
    ;;
esac
