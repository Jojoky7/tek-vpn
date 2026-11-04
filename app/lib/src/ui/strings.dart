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
  String get changeServer => t('Сменить страну', 'Change location');
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
  String get appSection => t('Приложение', 'App');
  String get developer => t('Для разработчиков', 'For developers');
  String get developerHint => t(
      'Эти настройки нужны, только когда что-то не работает. Меняйте их, если понимаете, зачем.',
      'These settings only matter when something does not work. Change them if you know why.');
  String get developerOn => t('Раздел «Для разработчиков» открыт', 'The developer settings are open');
  String developerTaps(int n) => ru
      ? 'Ещё ${_plural(n, 'нажатие', 'нажатия', 'нажатий')}, и откроется раздел для разработчиков'
      : '$n more tap${n == 1 ? '' : 's'} to open the developer settings';
  String get developerHide => t('Скрыть раздел', 'Hide this section');
  String get fragmentation => t('Фрагментация', 'Fragmentation');
  String get fragmentationHint => t(
      'Первый пакет соединения с сервером Tek режет на кусочки. Некоторые провайдеры по этому '
          'пакету узнают VPN и рвут соединение, а по кусочкам узнать не могут. Включена сразу; '
          'выключайте, только если без неё работает лучше.',
      'Tek cuts the first packet it sends to the server into pieces. Some providers recognize '
          'a VPN by that packet and drop the connection; they cannot do it with the pieces. On by '
          'default; turn it off only if things work better without it.');
  String get blockQuic => t('Блокировать QUIC', 'Block QUIC');
  String get blockQuicHint => t(
      'QUIC — быстрый протокол поверх UDP, им пользуются YouTube, Google и другие. Через VPN он '
          'часто тормозит или не работает совсем. Когда он заблокирован, браузер сразу берёт '
          'обычное соединение, и сайты открываются быстрее.',
      'QUIC is a fast protocol over UDP used by YouTube, Google and others. Through a VPN it is '
          'often slow or does not work at all. When it is blocked, the browser takes a normal '
          'connection at once and sites open faster.');
  String get verboseLog => t('Подробный журнал', 'Detailed log');
  String get verboseLogHint => t(
      'В журнал попадает каждое соединение: куда, через какой сервер и что пошло не так. '
          'Помогает найти причину проблемы. Tek с ним работает медленнее, поэтому выключите '
          'после проверки.',
      'Every connection goes into the log: where it went, through which server and what went '
          'wrong. It helps find the cause of a problem. Tek is slower with it, so turn it off '
          'when you are done.');
  String get logs => t('Журнал', 'Log');
  String get logsHint => t('Что делал Tek. Журнал можно скопировать и отправить в поддержку.',
      'What Tek did. You can copy the log and send it to support.');

  String get ruSites => t('Российские сайты', 'Russian sites');
  String get ruSitesHint => t(
      'Эти сайты открываются напрямую, без VPN: так они работают быстрее, а банки и Госуслуги '
          'не просят выключить VPN. Сюда входят все сайты в зонах .ru, .su и .рф, российские '
          'сервисы на других адресах и российские IP-адреса.',
      'These sites open directly, without the VPN: they work faster, and banks and Gosuslugi do '
          'not ask you to turn the VPN off. This covers every site in the .ru, .su and .рф zones, '
          'Russian services elsewhere and Russian IP addresses.');
  String get ruSitesOff =>
      t('Сейчас все сайты идут через VPN.', 'All sites go through the VPN now.');
  String get popularServices => t('Популярные сервисы', 'Popular services');
  String get popularHint =>
      t('Выключите сервис, чтобы он шёл через VPN.', 'Turn a service off to send it through the VPN.');
  String get mySites => t('Свои сайты', 'Your sites');
  String get mySitesHint => t('Работают всегда, вместе со всеми поддоменами.',
      'They always apply, with all their subdomains.');
  String get addSite => t('Добавить сайт', 'Add a site');
  String get siteDirect => t('Напрямую', 'Directly');
  String get siteVpn => t('Через VPN', 'Through the VPN');
  String get badSite => t('Это не похоже на адрес сайта', 'This does not look like a site address');
  String get fullList => t('Весь список', 'Full list');
  String fullListCount(int n) => ru
      ? 'Все сайты .ru, .su, .рф и ещё ${_plural(n, 'сайт', 'сайта', 'сайтов')}'
      : 'All .ru, .su and .рф sites and $n more';
  String get fullListHint =>
      t('Снимите галочку, чтобы сайт шёл через VPN.', 'Uncheck a site to send it through the VPN.');
  String get nothingFound => t('Ничего не найдено', 'Nothing found');

  String get appsHintOnly => t('Через VPN идут только отмеченные программы, остальные напрямую.',
      'Only the checked apps use the VPN; the others go directly.');
  String get appsHintExcept => t('Отмеченные программы идут напрямую, остальные через VPN.',
      'The checked apps go directly; the others use the VPN.');
  String get addApp => t('Добавить программу', 'Add an app');
  String get appNameHintWindows => t('Например, Telegram.exe', 'For example, Telegram.exe');
  String get appNameHintMac => t('Например, /Applications/Telegram.app', 'For example, /Applications/Telegram.app');
  String get badApp => t('Нужно имя программы, например Telegram.exe',
      'Type the program name, for example Telegram.exe');
  String get appsRunning => t('Запущенные программы', 'Running apps');
  String get appsRunningHint => t('Здесь программы, которые запущены сейчас. Если нужной нет, запустите её или добавьте по имени.',
      'These are the apps that run now. If yours is missing, start it or add it by name.');
  String get appsInstalled => t('Программы', 'Apps');
  String get appsChosen => t('Выбранные', 'Selected');
  String get appsMacNote => t(
      'Safari и некоторые системные программы выходят в сеть через службы macOS, поэтому '
          'правило для них может не сработать.',
      'Safari and some system apps go online through macOS services, so a rule for them may '
          'not work.');
  String get appsProxyNote => t(
      'В режиме «Системный прокси» правило работает для программ, которые идут через прокси. '
          'Чтобы оно действовало на все программы, выберите «Весь трафик».',
      'In "System proxy" mode the rule covers the apps that use the proxy. Choose "All traffic" '
          'to cover every app.');

  String get quickTile => t('Кнопка в шторке', 'Quick settings button');
  String get quickTileHint =>
      t('Включать VPN прямо из шторки уведомлений', 'Turn the VPN on from the notification shade');
  String get tileAdded => t('Кнопка Tek добавлена в шторку', 'The Tek button is in quick settings now');
  String get tileAlready => t('Кнопка Tek уже есть в шторке', 'The Tek button is already in quick settings');
  String get tileManual => t(
      'Опустите шторку двумя пальцами, нажмите на карандаш и перетащите кнопку Tek к остальным.',
      'Pull the shade down with two fingers, tap the pencil and drag the Tek button to the others.');
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
