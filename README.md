# Tek: готовые файлы

Собранные версии VPN-приложения Tek для Android, Windows и macOS. Для
подключения нужна ссылка подписки tekvpn.com. Код приложения лежит в ветке
[main](https://github.com/Jojoky7/tek-vpn/tree/main).

## Последняя версия: 1.2.1

| Система | Файл |
| --- | --- |
| Android | [Tek-1.2.1-android.apk](1.2.1/Tek-1.2.1-android.apk?raw=true) |
| Windows | [установщик](1.2.1/Tek-1.2.1-windows-x64-setup.exe?raw=true) или [без установки, zip](1.2.1/Tek-1.2.1-windows-x64-portable.zip?raw=true) |
| macOS | [Tek-1.2.1-macos.dmg](1.2.1/Tek-1.2.1-macos.dmg?raw=true) |

Контрольные суммы SHA-256 лежат в [SHA256SUMS.txt](1.2.1/SHA256SUMS.txt) рядом
с файлами каждой версии.

## Как установить

- **Android.** Откройте APK и разрешите установку из этого источника. Новая
  версия ставится поверх старой, подписка и настройки сохраняются.
- **Windows.** Запустите установщик. У программы пока нет цифровой подписи,
  поэтому Windows может показать «Windows защитила ваш компьютер»: нажмите
  «Подробнее», затем «Выполнить в любом случае».
- **macOS.** Откройте dmg и перетащите Tek в «Программы». Программа не
  подписана Apple, поэтому после установки один раз выполните в Терминале
  `xattr -cr /Applications/Tek.app`, иначе macOS скажет, что её не удаётся
  открыть. Для режима «Весь трафик» Tek один раз попросит пароль
  администратора.

## Все версии

В версиях с 1.0.2 по 1.0.7 менялись только программы для компьютеров,
поэтому файла для Android в них нет.

### 1.2.1, 5 ноября 2026

[Android](1.2.1/Tek-1.2.1-android.apk?raw=true) ·
[Windows](1.2.1/Tek-1.2.1-windows-x64-setup.exe?raw=true) ·
[Windows без установки](1.2.1/Tek-1.2.1-windows-x64-portable.zip?raw=true) ·
[macOS](1.2.1/Tek-1.2.1-macos.dmg?raw=true) ·
[суммы](1.2.1/SHA256SUMS.txt) ·
[код](https://github.com/Jojoky7/tek-vpn/tree/9bdc486e74fc6507e76330e4de2fffe27f7ffe7e)

- Сайт tekvpn.com открывается с включённым VPN: он всегда идёт через VPN, даже
  когда включено «Российские сайты напрямую». Раньше на некоторых сетях сайт с
  VPN не грузился.

### 1.2.0, 4 ноября 2026

[Android](1.2.0/Tek-1.2.0-android.apk?raw=true) ·
[Windows](1.2.0/Tek-1.2.0-windows-x64-setup.exe?raw=true) ·
[Windows без установки](1.2.0/Tek-1.2.0-windows-x64-portable.zip?raw=true) ·
[macOS](1.2.0/Tek-1.2.0-macos.dmg?raw=true) ·
[суммы](1.2.0/SHA256SUMS.txt) ·
[код](https://github.com/Jojoky7/tek-vpn/tree/80787dd9ba38e9ba067edcfa9e119832b57694f3)

- Из приложения убраны вход и регистрация по почте. Остались ссылка подписки
  и QR-код: ссылку берите в личном кабинете на tekvpn.com.
- Сеанс входа по почте, который хранили прошлые версии, стирается при первом
  запуске. Уже добавленная подписка остаётся.

### 1.1.0, 4 ноября 2026

[Android](1.1.0/Tek-1.1.0-android.apk?raw=true) ·
[Windows](1.1.0/Tek-1.1.0-windows-x64-setup.exe?raw=true) ·
[Windows без установки](1.1.0/Tek-1.1.0-windows-x64-portable.zip?raw=true) ·
[macOS](1.1.0/Tek-1.1.0-macos.dmg?raw=true) ·
[суммы](1.1.0/SHA256SUMS.txt) ·
[код](https://github.com/Jojoky7/tek-vpn/tree/0b76f5635195e858b81127bbb4f43df7a607a0db)

- Выбор приложений на всех системах: какие программы идут через VPN, а какие
  напрямую.
- Экран «Российские сайты»: популярные сервисы можно по одному пустить через
  VPN, свои сайты добавить напрямую или через VPN, весь список открывается с
  поиском.
- Фрагментация, блокировка QUIC и журнал перенесены в раздел «Для
  разработчиков» с пояснением к каждой настройке. Раздел открывается пятью
  нажатиями на версию в настройках.
- Android: кнопка Tek в шторке уведомлений.
- Волны при нажатии на кнопку, синий цвет и новые иконки.
- Компьютеры: приложение не зависает, если ядро не отвечает. На macOS VPN
  отключается, если приложение закрылось.

### 1.0.7, 29 октября 2026

[Windows](1.0.7/Tek-1.0.7-windows-x64-setup.exe?raw=true) ·
[macOS](1.0.7/Tek-1.0.7-macos.dmg?raw=true) ·
[суммы](1.0.7/SHA256SUMS.txt) ·
[код](https://github.com/Jojoky7/tek-vpn/tree/9250ba9018f5bc11abd38ba74b2e1ffc552ac1ec)

- macOS: пароль для режима «Весь трафик» спрашивается один раз, а не при
  каждом подключении.

### 1.0.6, 28 октября 2026

[Windows](1.0.6/Tek-1.0.6-windows-x64-setup.exe?raw=true) ·
[macOS](1.0.6/Tek-1.0.6-macos.dmg?raw=true) ·
[суммы](1.0.6/SHA256SUMS.txt) ·
[код](https://github.com/Jojoky7/tek-vpn/tree/eb04d98fde0826c31378a58e9ad29ff940c991e7)

- Windows, режим «Весь трафик»: каждое соединение мимо VPN получает свой
  маршрут через сетевую карту.

### 1.0.5, 28 октября 2026

[Windows](1.0.5/Tek-1.0.5-windows-x64-setup.exe?raw=true) ·
[macOS](1.0.5/Tek-1.0.5-macos.dmg?raw=true) ·
[суммы](1.0.5/SHA256SUMS.txt) ·
[код](https://github.com/Jojoky7/tek-vpn/tree/14871e6d5a3f44cf38c29947d20af56b23c83713)

- Windows, режим «Весь трафик»: у туннеля один маршрут по умолчанию, чтобы
  соединения мимо VPN не уходили в него.

### 1.0.4, 28 октября 2026

[Windows](1.0.4/Tek-1.0.4-windows-x64-setup.exe?raw=true) ·
[macOS](1.0.4/Tek-1.0.4-macos.dmg?raw=true) ·
[суммы](1.0.4/SHA256SUMS.txt) ·
[код](https://github.com/Jojoky7/tek-vpn/tree/bf0381400e68d1985f898789b6f63f5125d33de4)

- Windows, режим «Весь трафик»: соединения мимо VPN отправляются с адреса
  сетевой карты.

### 1.0.3, 28 октября 2026

[Windows](1.0.3/Tek-1.0.3-windows-x64-setup.exe?raw=true) ·
[macOS](1.0.3/Tek-1.0.3-macos.dmg?raw=true) ·
[суммы](1.0.3/SHA256SUMS.txt) ·
[код](https://github.com/Jojoky7/tek-vpn/tree/564664a0c1c9ccd14be1bff9675aec8f89d68809)

- Windows, режим «Весь трафик»: исправлена ошибка «Element not found» при
  включении.

### 1.0.2, 28 октября 2026

[Windows](1.0.2/Tek-1.0.2-windows-x64-setup.exe?raw=true) ·
[macOS](1.0.2/Tek-1.0.2-macos.dmg?raw=true) ·
[суммы](1.0.2/SHA256SUMS.txt) ·
[код](https://github.com/Jojoky7/tek-vpn/tree/36a7678dae59ca11d2c4bd12d192891df3240d39)

- Компьютеры: режим «Весь трафик» снова включается после отключения.

### 1.0.1, 27 октября 2026

[Android](1.0.1/Tek-1.0.1-android.apk?raw=true) ·
[Windows](1.0.1/Tek-1.0.1-windows-x64-setup.exe?raw=true) ·
[macOS](1.0.1/Tek-1.0.1-macos.dmg?raw=true) ·
[суммы](1.0.1/SHA256SUMS.txt) ·
[код](https://github.com/Jojoky7/tek-vpn/tree/a407b41b0bbc0133afee08c89a10ec8fce14cea6)

- Компьютеры: Tek подключается, даже если порт 10808 занят другим
  VPN-клиентом.
- Если подключиться не удалось, видна причина.

### 1.0.0, 27 октября 2026

[Android](1.0.0/Tek-1.0.0-android.apk?raw=true) ·
[Windows](1.0.0/Tek-1.0.0-windows-x64-setup.exe?raw=true) ·
[Windows без установки](1.0.0/Tek-1.0.0-windows-x64-portable.zip?raw=true) ·
[macOS](1.0.0/Tek-1.0.0-macos.dmg?raw=true) ·
[суммы](1.0.0/SHA256SUMS.txt) ·
[код](https://github.com/Jojoky7/tek-vpn/tree/9975b623e6adba9ee744dc63c241a5f23ef48800)

- Первая версия: подключение по ссылке подписки, выбор страны, российские
  сайты напрямую.
