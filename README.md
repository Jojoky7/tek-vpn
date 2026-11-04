# Tek

VPN-приложение TekVPN для Android, Windows и macOS. Подключается по ссылке
подписки tekvpn.com. Внутри Xray 26.3.27.

## Скачать Tek 1.1.0

| Система | Файл |
| --- | --- |
| Android | [Tek-1.1.0-android.apk](https://github.com/Jojoky7/tek-vpn/raw/releases/1.1.0/Tek-1.1.0-android.apk) |
| Windows | [установщик](https://github.com/Jojoky7/tek-vpn/raw/releases/1.1.0/Tek-1.1.0-windows-x64-setup.exe) или [без установки, zip](https://github.com/Jojoky7/tek-vpn/raw/releases/1.1.0/Tek-1.1.0-windows-x64-portable.zip) |
| macOS | [Tek-1.1.0-macos.dmg](https://github.com/Jojoky7/tek-vpn/raw/releases/1.1.0/Tek-1.1.0-macos.dmg) |

Все версии, как установить и что в них менялось: ветка
[releases](https://github.com/Jojoky7/tek-vpn/tree/releases).

## Что где

| Папка | Что внутри |
| --- | --- |
| `app/` | Приложение на Flutter: экраны, подписка, выбор сервера, настройки |
| `app/android/` | VPN-служба Android, плитка в шторке, выбор приложений |
| `app/windows/installer/` | Установщик Windows (Inno Setup) |
| `core/` | Ядро на Go: Xray, проверка серверов, `tek-core` для Windows и macOS, библиотека для Android |
| `core/cmd/geotrim/` | Сборка урезанных geoip.dat и geosite.dat (только Россия) |
| `tool/` | Иконки, сборка ядра для Android, скрипты CI |
| `docs/PLAN.md` | Решения и план |

## Как устроено подключение

```
Экраны (Flutter, общие для всех систем)
        ↓
Слой подключения: подписка, выбор страны, пинг, конфиг Xray
        ↓
Ядро: Xray 26.3.27 (адаптер, чтобы позже добавить второе ядро)
        ↓
Android: Xray в процессе приложения, VpnService отдаёт ему TUN
Windows: tek-core.exe, системный прокси или «весь трафик» через wintun
macOS:   tek-core, системный прокси или «весь трафик» через utun
```

На компьютерах приложение запускает `tek-core` и говорит с ним по HTTP на
127.0.0.1 со случайным токеном. Для режима «весь трафик» `tek-core`
запускается с правами администратора. Если приложение закрылось аварийно,
`tek-core` сам возвращает настройки сети.

На macOS права нужны один раз: приложение ставит помощник, копию `tek-core`
в `/Library/PrivilegedHelperTools/com.tekvpn.core`, который launchd держит
запущенным (`/Library/LaunchDaemons/com.tekvpn.core.plist`). Порт и токен он
пишет в `/Library/Application Support/Tek/helper-<uid>.json`, читать этот файл
может только этот пользователь. После обновления приложения помощник
ставится заново, с одним запросом пароля. Удалить его:

```
sudo launchctl bootout system/com.tekvpn.core
sudo rm /Library/LaunchDaemons/com.tekvpn.core.plist /Library/PrivilegedHelperTools/com.tekvpn.core
sudo rm -r "/Library/Application Support/Tek"
```

## Что идёт мимо VPN

- Российские сайты: правило `geosite:category-ru` (все .ru, .su, .рф и
  российские сервисы на других адресах) и `geoip:ru`. Популярные сервисы
  (`app/lib/src/xray/ru_sites.dart`) можно отправить через VPN по одному, свои
  сайты добавить напрямую или через VPN. Сайты «через VPN» стоят в правилах
  раньше, поэтому перебивают общий список.
- Приложения. На Android их оставляет вне VPN сама VpnService. На
  компьютерах это правила Xray по программе (`process`): на Windows по имени
  (`Telegram.exe`), на macOS по папке приложения
  (`/Applications/Telegram.app/`). Xray 26.3.27 умеет узнавать программу
  соединения только на Windows и Linux; для macOS `tek-core` собирается с
  копией Xray, в которую добавлен `core/_xray/common/net/find_process_darwin.go`
  (поиск по `net.inet.*.pcblist_n`, код в `core/darwinproc`). Копию готовит
  `core/_xray/workspace.sh`.

Настройки для разработчиков (фрагментация, блокировка QUIC, подробный журнал,
журнал) спрятаны: раздел появляется после пяти нажатий на версию в
настройках.

## Сборка

Нужны Flutter 3.47.8, Go 1.26.

- Android: `tool/build-android-core.sh`, затем в `app/`:
  `flutter build apk --release --target-platform android-arm,android-arm64`.
  Для подписи нужен `app/android/key.properties` с ключом. Ключа в репозитории
  нет и не должно быть.
- Windows и macOS: GitHub Actions, workflow **Desktop**. Запуск вручную
  (Actions → Desktop → Run workflow) кладёт файлы в артефакты сборки. Тег
  `v1.2.3` дополнительно публикует их в Releases. `tek-core` для macOS
  вручную: `GOWORK="$(_xray/workspace.sh)" GOOS=darwin go build ./cmd/tek-core`
  в `core/`.
- Иконки: `python3 tool/brand/make_icons.py` рисует их все заново.
- Выпуск: файлы новой версии кладутся в ветку `releases`, в папку с номером
  версии вместе с SHA256SUMS.txt, и описываются в README этой ветки. Ветка
  не связана с `main`, поэтому сборки не попадают в код и в CI. Ссылки
  «Скачать» в начале этого README переводятся на новую версию.

Тесты: `flutter test` в `app/`, `go test ./...` в `core/`.
