import 'server.dart';

/// What the subscription says about itself, from its headers or from
/// `#key: value` lines in the body.
class SubscriptionInfo {
  const SubscriptionInfo({
    this.title,
    this.upload,
    this.download,
    this.total,
    this.expire,
    this.updateIntervalHours,
    this.supportUrl,
    this.webPageUrl,
    this.announce,
    this.fragment,
  });

  final String? title;
  final int? upload;
  final int? download;

  /// Traffic limit in bytes; 0 or null means unlimited.
  final int? total;
  final DateTime? expire;
  final int? updateIntervalHours;
  final String? supportUrl;
  final String? webPageUrl;
  final String? announce;

  /// Fragmentation requested for the whole subscription.
  final FragmentSettings? fragment;

  int get used => (upload ?? 0) + (download ?? 0);

  bool get unlimited => total == null || total == 0;

  bool get expired => expire != null && expire!.isBefore(DateTime.now());

  bool get trafficOver => !unlimited && used >= total!;

  SubscriptionInfo merge(SubscriptionInfo other) => SubscriptionInfo(
        title: other.title ?? title,
        upload: other.upload ?? upload,
        download: other.download ?? download,
        total: other.total ?? total,
        expire: other.expire ?? expire,
        updateIntervalHours: other.updateIntervalHours ?? updateIntervalHours,
        supportUrl: other.supportUrl ?? supportUrl,
        webPageUrl: other.webPageUrl ?? webPageUrl,
        announce: other.announce ?? announce,
        fragment: other.fragment ?? fragment,
      );

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (upload != null) 'upload': upload,
        if (download != null) 'download': download,
        if (total != null) 'total': total,
        if (expire != null) 'expire': expire!.millisecondsSinceEpoch,
        if (updateIntervalHours != null) 'updateIntervalHours': updateIntervalHours,
        if (supportUrl != null) 'supportUrl': supportUrl,
        if (webPageUrl != null) 'webPageUrl': webPageUrl,
        if (announce != null) 'announce': announce,
        if (fragment != null) 'fragment': fragment!.toJson(),
      };

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) =>
      SubscriptionInfo(
        title: json['title'] as String?,
        upload: json['upload'] as int?,
        download: json['download'] as int?,
        total: json['total'] as int?,
        expire: json['expire'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['expire'] as int),
        updateIntervalHours: json['updateIntervalHours'] as int?,
        supportUrl: json['supportUrl'] as String?,
        webPageUrl: json['webPageUrl'] as String?,
        announce: json['announce'] as String?,
        fragment: json['fragment'] == null
            ? null
            : FragmentSettings.fromJson(
                Map<String, dynamic>.from(json['fragment'] as Map)),
      );
}

class Subscription {
  Subscription({
    required this.url,
    required this.info,
    required this.servers,
    required this.updatedAt,
  });

  final String url;
  final SubscriptionInfo info;
  final List<ServerNode> servers;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'url': url,
        'info': info.toJson(),
        'servers': [for (final s in servers) s.toJson()],
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        url: json['url'] as String,
        info: SubscriptionInfo.fromJson(
            Map<String, dynamic>.from(json['info'] as Map? ?? const {})),
        servers: [
          for (final s in (json['servers'] as List? ?? const []))
            ServerNode.fromJson(Map<String, dynamic>.from(s as Map))
        ],
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int? ?? 0),
      );
}
