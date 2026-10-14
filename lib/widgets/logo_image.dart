import 'package:flutter/material.dart';

import '../core/time/clock.dart';
import '../theme/tokens.dart';
import 'bidi_text.dart';

/// Image URLs that failed to load recently, so scrolling lists don't retry
/// them on every build.
///
/// A definitive failure (HTTP 4xx other than 408 and 429) is remembered for
/// [definitiveTtl]. Anything else (no network yet at boot, DNS, timeouts, 5xx,
/// bad image data) is remembered only for [transientTtl], so images come back
/// with the network; call [clearTransient] when connectivity returns to retry
/// them at once. Insertion-ordered and capped at [maxEntries] (oldest dropped
/// first).
abstract final class FailedImageCache {
  static const maxEntries = 2000;
  static const transientTtl = Duration(minutes: 10);
  static const definitiveTtl = Duration(hours: 6);

  /// Time source for expiry; tests swap in a fake.
  static Clock clock = const SystemClock();

  static final Map<String, ({DateTime until, bool definitive})> _entries = {};

  /// Whether [url] failed recently; an expired entry is dropped.
  static bool contains(String url) {
    final entry = _entries[url];
    if (entry == null) return false;
    if (clock.now().isBefore(entry.until)) return true;
    _entries.remove(url);
    return false;
  }

  /// Records a failed load of [url]; [error] decides how long it is kept.
  static void add(String url, {Object? error}) {
    final definitive = isDefinitive(error);
    final ttl = definitive ? definitiveTtl : transientTtl;
    _entries
      ..remove(url)
      ..[url] = (until: clock.now().add(ttl), definitive: definitive);
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Whether [error] means the image will not load on a retry either.
  static bool isDefinitive(Object? error) => switch (error) {
    NetworkImageLoadException(:final statusCode) =>
      statusCode >= 400 &&
          statusCode < 500 &&
          statusCode != 408 &&
          statusCode != 429,
    _ => false,
  };

  /// Forgets transient failures, e.g. when the network comes back.
  static void clearTransient() => _entries.removeWhere((_, e) => !e.definitive);

  static int get length => _entries.length;

  static void clear() => _entries.clear();
}

final _prefixTag = RegExp(r'^\s*(\|[^|]{1,6}\||[A-Za-z]{2,3}\s*[:|])\s*');
final _separators = RegExp(r'[\s\-_|:.,/\\()\[\]{}+*#@!]+');
final _alnum = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _qualityTag = RegExp(
  r'^(uhd|fhd|hd|sd|hevc|h265|h264|4k|8k|1080p?|720p?|backup|vip)$',
  caseSensitive: false,
);

/// One or two initials for an avatar: "Example News HD" -> "EN",
/// "Channel 2" -> "C2", "الأخبار" -> "أ" (definite article skipped). Arabic
/// names get a single letter because joined letters read as a word.
String initialsFor(String name) {
  final tokens = name
      .replaceFirst(_prefixTag, '')
      .split(_separators)
      .where(
        (t) => t.isNotEmpty && _alnum.hasMatch(t) && !_qualityTag.hasMatch(t),
      )
      .toList();
  if (tokens.isEmpty) {
    final any = name.characters.where(_alnum.hasMatch).firstOrNull;
    return any?.toUpperCase() ?? '?';
  }
  String firstOf(String token) {
    var t = token;
    if (t.startsWith('ال') && t.characters.length > 3) t = t.substring(2);
    return t.characters.firstWhere(_alnum.hasMatch, orElse: () => '?');
  }

  final first = firstOf(tokens.first);
  if (textDirectionFor(first) == TextDirection.rtl || tokens.length < 2) {
    return first.toUpperCase();
  }
  final second = firstOf(tokens[1]);
  if (textDirectionFor(second) == TextDirection.rtl) return first.toUpperCase();
  return '$first$second'.toUpperCase();
}

/// Stable avatar colour for [name].
Color avatarColorFor(String name) {
  var h = 0;
  for (final unit in name.codeUnits) {
    h = (h * 31 + unit) & 0x7fffffff;
  }
  return AppColors.avatarPalette[h % AppColors.avatarPalette.length];
}

/// Coloured square with [initialsFor] of [name].
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.borderRadius = Radii.smAll,
  });

  final String name;
  final double size;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: avatarColorFor(name),
        borderRadius: borderRadius,
      ),
      padding: EdgeInsets.all(size * 0.12),
      child: FittedBox(
        child: Text(
          initialsFor(name),
          maxLines: 1,
          style: TextStyle(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// Channel logo from [url], decoded at display size ([Image.cacheWidth]).
///
/// Shows an [InitialsAvatar] while loading, when [url] is empty or not
/// http(s), and on error; failed URLs go into [FailedImageCache] and are not
/// requested again until that entry expires.
class LogoImage extends StatelessWidget {
  const LogoImage({
    super.key,
    required this.url,
    required this.name,
    this.size = 40,
    this.borderRadius = Radii.smAll,
    this.fit = BoxFit.contain,
  });

  final String? url;
  final String name;
  final double size;
  final BorderRadius borderRadius;
  final BoxFit fit;

  static bool _isHttp(String url) =>
      url.startsWith('http://') || url.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    final avatar = InitialsAvatar(
      name: name,
      size: size,
      borderRadius: borderRadius,
    );
    final u = url?.trim();
    if (u == null || u.isEmpty || !_isHttp(u) || FailedImageCache.contains(u)) {
      return avatar;
    }
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final cacheWidth = (size * dpr).round().clamp(1, 1024);
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Image.network(
          u,
          width: size,
          height: size,
          fit: fit,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) =>
              frame == null && !sync ? avatar : child,
          errorBuilder: (context, error, stackTrace) {
            FailedImageCache.add(u, error: error);
            return avatar;
          },
        ),
      ),
    );
  }
}
