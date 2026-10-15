// Pure form logic of the source editor: field validation, User-Agent
// presets and the config the editor saves. No Flutter, no I/O.
import '../../core/net/http.dart';
import '../../core/net/redact.dart';
import '../../sources/models.dart';
import '../../sources/xtream/xtream_urls.dart';

/// Editable fields of the source editor.
enum SourceField {
  name,
  url,
  file,
  server,
  username,
  password,
  userAgent,
  referer,
  epgUrl,
}

/// Why a field is not acceptable.
enum SourceFieldError {
  /// Empty but needed.
  required,

  /// Not an `http(s)://host` address.
  invalidUrl,

  /// Still holds the masked (`***`) copy of a saved URL with credentials,
  /// edited: the hidden credentials would be lost.
  maskedUrl,
}

/// The [kUserAgentPresets] key of the app's default User-Agent.
const kDefaultUserAgentPreset = 'Default';

/// The preset whose value is [userAgent] ([kDefaultUserAgentPreset] for
/// none), or null for a custom value.
String? userAgentPresetFor(String? userAgent) {
  final ua = userAgent?.trim() ?? '';
  if (ua.isEmpty) return kDefaultUserAgentPreset;
  for (final MapEntry(:key, :value) in kUserAgentPresets.entries) {
    if (value == ua) return key;
  }
  return null;
}

/// The User-Agent to save for [preset] (null: custom [custom]). The default
/// preset saves null, so the app default applies and can change later.
String? userAgentFor(String? preset, String custom) {
  if (preset == null) {
    final value = custom.trim();
    return value.isEmpty ? null : value;
  }
  if (preset == kDefaultUserAgentPreset) return null;
  return kUserAgentPresets[preset];
}

/// Whether [text] is an `http://` or `https://` URL with a host.
bool isHttpUrl(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  return (scheme == 'http' || scheme == 'https') &&
      uri.host.isNotEmpty &&
      !uri.host.contains('%') &&
      !text.trim().contains(' ');
}

/// Whether [text] is a usable Xtream server address (the scheme may be
/// left out; `http://` is assumed).
bool isXtreamServer(String text) {
  if (text.trim().isEmpty) return false;
  return XtreamUrls.parseBase(XtreamUrls.normalizeBase(text)) != null;
}

/// What the editor holds, as plain values.
class SourceFormValues {
  const SourceFormValues({
    required this.kind,
    this.name = '',
    this.url = '',
    this.savedMaskedUrl,
    this.hasFile = false,
    this.server = '',
    this.username = '',
    this.password = '',
    this.hasSavedPassword = false,
    this.userAgentPreset = kDefaultUserAgentPreset,
    this.customUserAgent = '',
    this.referer = '',
    this.epgUrl = '',
    this.savedEpgUrl,
  });

  final SourceKind kind;
  final String name;

  /// Playlist URL ([SourceKind.m3uUrl]).
  final String url;

  /// The saved playlist URL as shown (credentials masked), when editing.
  final String? savedMaskedUrl;

  /// Whether a playlist file is picked or saved ([SourceKind.m3uFile]).
  final bool hasFile;
  final String server;
  final String username;
  final String password;

  /// Editing a saved Xtream source: an empty password keeps the saved one.
  final bool hasSavedPassword;

  /// A [kUserAgentPresets] key, or null for [customUserAgent].
  final String? userAgentPreset;
  final String customUserAgent;
  final String referer;
  final String epgUrl;

  /// The saved manual guide URL as shown (masked), when editing.
  final String? savedEpgUrl;
}

/// Problems of [v], by field, in display order. Empty means valid.
Map<SourceField, SourceFieldError> validateSourceForm(SourceFormValues v) {
  final errors = <SourceField, SourceFieldError>{};
  switch (v.kind) {
    case SourceKind.m3uUrl:
      final url = v.url.trim();
      if (url.isEmpty) {
        errors[SourceField.url] = SourceFieldError.required;
      } else if (url != v.savedMaskedUrl && url.contains(redactedMark)) {
        errors[SourceField.url] = SourceFieldError.maskedUrl;
      } else if (!isHttpUrl(url)) {
        errors[SourceField.url] = SourceFieldError.invalidUrl;
      }
    case SourceKind.m3uFile:
      if (!v.hasFile) errors[SourceField.file] = SourceFieldError.required;
    case SourceKind.xtream:
      if (v.server.trim().isEmpty) {
        errors[SourceField.server] = SourceFieldError.required;
      } else if (!isXtreamServer(v.server)) {
        errors[SourceField.server] = SourceFieldError.invalidUrl;
      }
      if (v.username.trim().isEmpty) {
        errors[SourceField.username] = SourceFieldError.required;
      }
      if (v.password.isEmpty && !v.hasSavedPassword) {
        errors[SourceField.password] = SourceFieldError.required;
      }
  }
  if (v.userAgentPreset == null && v.customUserAgent.trim().isEmpty) {
    errors[SourceField.userAgent] = SourceFieldError.required;
  }
  final referer = v.referer.trim();
  if (referer.isNotEmpty && !isHttpUrl(referer)) {
    errors[SourceField.referer] = SourceFieldError.invalidUrl;
  }
  final epg = v.epgUrl.trim();
  if (epg.isNotEmpty && epg != v.savedEpgUrl) {
    if (epg.contains(redactedMark)) {
      errors[SourceField.epgUrl] = SourceFieldError.maskedUrl;
    } else if (!isHttpUrl(epg)) {
      errors[SourceField.epgUrl] = SourceFieldError.invalidUrl;
    }
  }
  return errors;
}
