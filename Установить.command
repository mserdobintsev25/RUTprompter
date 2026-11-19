#!/bin/bash
# RUTprompter — установка в один клик. Запуск: двойной щелчок по этому файлу в Finder.
cd "$(dirname "$0")" || exit 1

blue=$'\033[1;34m'; green=$'\033[1;32m'; red=$'\033[1;31m'; off=$'\033[0m'
step() { echo; echo "${blue}▸ $1${off}"; }
ok()   { echo "${green}✓ $1${off}"; }
fail() { echo; echo "${red}✗ $1${off}"; echo; echo "Нажмите любую клавишу, чтобы закрыть окно."; read -n 1; exit 1; }

echo "${blue}RUTprompter — суфлёр, который следует за голосом${off}"
echo "Установка займёт 2–5 минут. Окно можно не трогать."

# 1. Версия macOS
step "Проверка macOS"
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "${MAJOR:-0}" -ge 13 ] || fail "Нужна macOS 13 или новее (сейчас $(sw_vers -productVersion))."
ok "macOS $(sw_vers -productVersion)"

# 2. Инструменты разработчика (компилятор Swift)
step "Инструменты разработчика"
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  xcode-select --install 2>/dev/null
  echo "Появилось окно установки — нажмите «Установить» и дождитесь конца."
  echo "Потом снова дважды щёлкните «Установить.command»."
  echo; echo "Нажмите любую клавишу, чтобы закрыть окно."; read -n 1; exit 0
fi
ok "$(swift --version 2>/dev/null | head -1)"

# 3. Сборка и установка в «Программы»
step "Сборка RUTprompter"
chmod +x build.sh
./build.sh install || fail "Сборка не удалась. Скопируйте весь текст из этого окна и пришлите разработчику."
[ -d /Applications/RUTprompter.app ] || fail "Приложение не появилось в «Программах»."
ok "RUTprompter установлен в «Программы»"

# 4. Разрешения и язык распознавания
step "Последний шаг — микрофон и распознавание речи"
echo "При первом нажатии «Старт» в режиме «Голос» macOS дважды спросит разрешение:"
echo "  • доступ к микрофону;"
echo "  • доступ к распознаванию речи."
echo "Нажмите «Разрешить» в обоих окнах. Звук обрабатывается только на этом Mac."
echo
echo "Чтобы распознавание работало без интернета, нужна офлайн-диктовка нужного языка:"
echo "  Системные настройки → Клавиатура → Диктовка → Язык → добавьте «Русский»."
echo
read -r -p "Открыть настройки клавиатуры сейчас? [y/N] " answer
case "$answer" in y|Y|д|Д) open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension" ;; esac

echo
ok "Готово! Приложение уже открыто. Вставьте текст сценария и нажмите «Старт»."
echo "Если второй экран подключён по HDMI, вывод откроется на нём сам."
echo; echo "Нажмите любую клавишу, чтобы закрыть окно."; read -n 1
