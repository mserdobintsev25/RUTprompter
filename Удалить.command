#!/bin/bash
# RUTprompter — полное удаление. Запуск: двойной щелчок в Finder.
# Пригодится, если само приложение не запускается.

blue=$'\033[1;34m'; green=$'\033[1;32m'; off=$'\033[0m'
ID="local.rutprompter.app"
L="$HOME/Library"
DATA="$L/Application Support/RUTprompter"

echo "${blue}RUTprompter — полное удаление${off}"
echo
echo "Будут удалены: приложение, настройки, журналы, кэши, отчёты о сбоях и разрешения RUTprompter."
echo "Исходники проекта (эта папка) не трогаются."
echo
read -r -p "Продолжить? [y/N] " answer
case "$answer" in y|Y|д|Д) ;; *) echo "Отменено."; read -n 1; exit 0 ;; esac

# Сохранённый сценарий — это ваши данные, по умолчанию его оставляем.
REMOVE_DATA=n
if [ -d "$DATA" ]; then
  read -r -p "Удалить и сохранённый сценарий ($DATA)? [y/N] " m
  case "$m" in y|Y|д|Д) REMOVE_DATA=y ;; esac
fi

pkill -x RUTprompter 2>/dev/null && sleep 1

# Файлы
rm -rf "/Applications/RUTprompter.app" \
       "$L/Logs/RUTprompter" \
       "$L/Caches/$ID" \
       "$L/HTTPStorages/$ID" "$L/HTTPStorages/$ID.binarycookies" \
       "$L/Saved Application State/$ID.savedState" \
       "$L/WebKit/$ID"
rm -f "$L/Logs/DiagnosticReports/"RUTprompter*.ips "$L/Logs/DiagnosticReports/"RUTprompter*.crash 2>/dev/null
if [ "$REMOVE_DATA" = y ]; then
  rm -rf "$DATA"
else
  # Отладочный журнал не нужен в любом случае.
  rm -f "$DATA/debug.log"
fi

# Настройки (через cfprefsd, чтобы не вернулись из кэша)
defaults delete "$ID" >/dev/null 2>&1
rm -f "$L/Preferences/$ID.plist"

# Разрешения конфиденциальности (микрофон, распознавание речи)
tccutil reset All "$ID" >/dev/null 2>&1

echo
echo "${green}✓ RUTprompter удалён.${off}"
[ "$REMOVE_DATA" = y ] || { [ -d "$DATA" ] && echo "Сценарий сохранён: $DATA"; }
echo
echo "Сама папка проекта осталась — её можно просто отправить в Корзину."
echo
echo "Нажмите любую клавишу, чтобы закрыть окно."; read -n 1
