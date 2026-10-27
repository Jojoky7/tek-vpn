import 'dart:ui' show PlatformDispatcher;

/// Texts of the app in Russian and English. Russian is the main language;
/// English is used when the device is not set to Russian.
class S {
  S._(this.ru);

  final bool ru;

  static S current = S._(true);

  /// language: system, ru or en.
  static void use(String language) {
    final ru = switch (language) {
      'ru' => true,
      'en' => false,
      _ => _systemIsRussian(),
    };
    current = S._(ru);
  }

  static bool _systemIsRussian() {
    final locales = PlatformDispatcher.instance.locales;
    if (locales.isEmpty) return true;
    final code = locales.first.languageCode;
    return const {'ru', 'uk', 'be', 'kk', 'ky', 'uz', 'tg', 'hy', 'az', 'ka'}
        .contains(code);
  }

  String t(String ruText, String enText) => ru ? ruText : enText;

  String get disconnected => t('Не подключено', 'Not connected');
  String get connecting => t('Подключение…', 'Connecting…');
  String get connected => t('Подключено', 'Connected');
  String get disconnecting => t('Отключение…', 'Disconnecting…');
  String get fastest => t('Самый быстрый', 'Fastest');
  String get fastestHint => t('Tek выберет сервер сам', 'Tek picks the server');
  String get servers => t('Страны', 'Locations');
  String get check => t('Проверить', 'Check');
  String get checking => t('Проверка…', 'Checking…');
  String get notAnswering => t('не отвечает', 'not answering');

  String get addSubscription => t('Добавить подписку', 'Add subscription');
  String get subscriptionLink => t('Ссылка на подписку', 'Subscription link');
  String get paste => t('Вставить', 'Paste');
  String get scanQr => t('Сканировать QR-код', 'Scan QR code');
  String get signInWithEmail => t('Войти по почте', 'Sign in with email');
  String get or => t('или', 'or');
  String get add => t('Добавить', 'Add');
  String get addHint => t(
      'Вставьте ссылку из личного кабинета или бота, отсканируйте QR-код или войдите по почте.',
      'Paste the link from your account or the bot, scan the QR code or sign in with email.');

  String get email => t('Почта', 'Email');
  String get password => t('Пароль', 'Password');
  String get signIn => t('Войти', 'Sign in');
  String get register => t('Зарегистрироваться', 'Create account');
  String get haveAccount => t('Уже есть аккаунт? Войти', 'Have an account? Sign in');
  String get noAccount => t('Нет аккаунта? Регистрация', 'No account? Create one');
  String get account => t('Аккаунт', 'Account');
  String get signOut => t('Выйти из аккаунта', 'Sign out');

  String trafficLeft(String left, String total) =>
      t('Осталось $left из $total', '$left of $total left');
  String get unlimited => t('Трафик без ограничений', 'Unlimited traffic');
  String until(String date) => t('до $date', 'until $date');
  String get expired => t('Подписка закончилась', 'Subscription has ended');
  String get trafficOver => t('Трафик закончился', 'No traffic left');
  String daysLeft(int days) => ru
      ? 'ещё ${_plural(days, 'день', 'дня', 'дней')}'
      : '$days day${days == 1 ? '' : 's'} left';

  String get settings => t('Настройки', 'Settings');
  String get subscription => t('Подписка', 'Subscription');
  String get refresh => t('Обновить', 'Refresh');
  String updated(String when) => t('Обновлено $when', 'Updated $when');
  String get remove => t('Удалить', 'Remove');
  String get removeConfirm =>
      t('Удалить подписку с этого устройства?', 'Remove the subscription from this device?');
  String get cancel => t('Отмена', 'Cancel');
  String get ok => t('Понятно', 'OK');

  String get connection => t('Подключение', 'Connection');
  String get mode => t('Режим', 'Mode');
  String get modeProxy => t('Системный прокси', 'System proxy');
  String get modeProxyHint => t('Браузеры и большинство программ. Без прав администратора.',
      'Browsers and most apps. No administrator rights needed.');
  String get modeTun => t('Весь трафик', 'All traffic');
  String get modeTunHint => t('Все программы и игры. Попросит права администратора.',
      'Every app and game. Asks for administrator rights.');
  String get ruDirect => t('Российские сайты напрямую', 'Russian sites directly');
  String get ruDirectHint => t('Банки, Госуслуги и маркетплейсы работают без VPN',
      'Russian banks and services open without the VPN');
  String get apps => t('Приложения', 'Apps');
  String get appsAll => t('Все приложения через VPN', 'All apps use the VPN');
  String get appsAllShort => t('Все', 'All');
  String get subscriptionAdded => t('Подписка добавлена', 'Subscription added');
  String get hiddenToTray => t(
      'Tek продолжит работать в фоне, VPN не отключится. Открыть окно или выйти можно через значок Tek рядом с часами.',
      'Tek keeps running in the background and the VPN stays on. Use the Tek icon next to the clock to open the window or quit.');
  String get appsOnly => t('Только выбранные', 'Only selected apps');
  String get appsExcept => t('Все, кроме выбранных', 'All except selected');
  String get search => t('Поиск', 'Search');
  String selectedCount(int n) => t('Выбрано: $n', 'Selected: $n');
  String get advanced => t('Дополнительно', 'Advanced');
  String get fragmentation => t('Фрагментация', 'Fragmentation');
  String get fragmentationHint =>
      t('Помогает, если провайдер мешает подключению', 'Helps when the provider blocks VPN');
  String get blockQuic => t('Блокировать QUIC', 'Block QUIC');
  String get blockQuicHint =>
      t('Сайты быстрее открываются через VPN', 'Sites load faster through the VPN');
  String get verboseLog => t('Подробный журнал', 'Detailed log');
  String get logs => t('Журнал', 'Log');
  String get copy => t('Копировать', 'Copy');
  String get copied => t('Скопировано', 'Copied');
  String get emptyLog => t('Журнал пуст', 'The log is empty');
  String get about => t('О приложении', 'About');
  String get version => t('Версия', 'Version');
  String get support => t('Поддержка', 'Support');
  String get language => t('Язык', 'Language');
  String get languageSystem => t('Как в системе', 'System');

  String get trayOpen => t('Открыть Tek', 'Open Tek');
  String get trayConnect => t('Подключить', 'Connect');
  String get trayDisconnect => t('Отключить', 'Disconnect');
  String get trayQuit => t('Выйти', 'Quit');

  String error(String key) => switch (key) {
        'badLink' => t('Это не похоже на ссылку подписки', 'This does not look like a subscription link'),
        'sub_notFound' => t('Подписка не найдена. Проверьте ссылку.', 'Subscription not found. Check the link.'),
        'sub_network' => t('Нет связи с сервером. Проверьте интернет.', 'Cannot reach the server. Check the internet.'),
        'sub_format' => t('Не удалось прочитать подписку', 'Could not read the subscription'),
        'sub_http' => t('Сервер подписки ответил ошибкой', 'The subscription server returned an error'),
        'noSubscription' => t('Сначала добавьте подписку', 'Add a subscription first'),
        'vpnDenied' => t('Нужно разрешить Tek создавать VPN', 'Allow Tek to set up a VPN'),
        'adminDenied' => t(
            'Для режима «Весь трафик» нужны права администратора. Можно выбрать «Системный прокси» в настройках.',
            '"All traffic" needs administrator rights. You can switch to "System proxy" in the settings.'),
        'connectFailed' => t('Не удалось подключиться', 'Could not connect'),
        'connectionLost' => t('Соединение прервалось', 'The connection dropped'),
        'gmailOnly' => t('Регистрация только с адресом @gmail.com', 'Only @gmail.com addresses can register'),
        'shortPassword' => t('Пароль должен быть не короче 8 символов', 'The password needs at least 8 characters'),
        'emailTaken' => t('Эта почта уже зарегистрирована. Войдите.', 'This email is already registered. Sign in.'),
        'signInFailed' => t('Неверная почта или пароль', 'Wrong email or password'),
        'noKeys' => t('В аккаунте пока нет подписки', 'The account has no subscription yet'),
        'serverTrouble' => t('Сервер не отвечает. Выберите другую страну.', 'The server does not answer. Pick another location.'),
        _ => t('Что-то пошло не так', 'Something went wrong'),
      };

  String bytes(num value) {
    const ruUnits = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
    const enUnits = ['B', 'KB', 'MB', 'GB', 'TB'];
    final units = ru ? ruUnits : enUnits;
    var v = value.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    final text = v >= 100 || i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${ru ? text.replaceAll('.', ',') : text} ${units[i]}';
  }

  String speed(num bytesPerSecond) => '${bytes(bytesPerSecond)}/${t('с', 's')}';

  String ms(int v) => t('$v мс', '$v ms');

  String date(DateTime d) {
    const ruMonths = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля',
        'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    const enMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
        'Nov', 'Dec'];
    final local = d.toLocal();
    return ru
        ? '${local.day} ${ruMonths[local.month - 1]} ${local.year}'
        : '${enMonths[local.month - 1]} ${local.day}, ${local.year}';
  }

  String ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return t('только что', 'just now');
    if (diff.inHours < 1) {
      return ru ? '${_plural(diff.inMinutes, 'минуту', 'минуты', 'минут')} назад' : '${diff.inMinutes} min ago';
    }
    if (diff.inDays < 1) {
      return ru ? '${_plural(diff.inHours, 'час', 'часа', 'часов')} назад' : '${diff.inHours} h ago';
    }
    return date(d);
  }

  static String _plural(int n, String one, String few, String many) {
    final mod10 = n % 10, mod100 = n % 100;
    final word = (mod10 == 1 && mod100 != 11)
        ? one
        : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14))
            ? few
            : many;
    return '$n $word';
  }
}
