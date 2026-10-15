import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/net/http.dart';
import 'package:iptv_player/features/sources/source_form.dart';
import 'package:iptv_player/sources/models.dart';

void main() {
  group('validateSourceForm', () {
    test('M3U link: required, then an http(s) URL', () {
      expect(
        validateSourceForm(const SourceFormValues(kind: SourceKind.m3uUrl)),
        {SourceField.url: SourceFieldError.required},
      );
      for (final bad in [
        'example.com/list.m3u',
        'ftp://example.com/list.m3u',
        'http://',
        'http://bad host/x.m3u',
        'file:///sdcard/list.m3u',
      ]) {
        expect(
          validateSourceForm(
            SourceFormValues(kind: SourceKind.m3uUrl, url: bad),
          ),
          {SourceField.url: SourceFieldError.invalidUrl},
          reason: bad,
        );
      }
      for (final good in [
        'http://example.com/list.m3u',
        ' https://example.com:8443/get.php?username=u&password=p ',
        'HTTP://EXAMPLE.COM/a',
      ]) {
        expect(
          validateSourceForm(
            SourceFormValues(kind: SourceKind.m3uUrl, url: good),
          ),
          isEmpty,
          reason: good,
        );
      }
    });

    test('M3U link: an edited masked URL must be typed again', () {
      const masked = 'http://h.example/get.php?username=***&password=***';
      expect(
        validateSourceForm(
          const SourceFormValues(
            kind: SourceKind.m3uUrl,
            url: masked,
            savedMaskedUrl: masked,
          ),
        ),
        isEmpty,
      );
      expect(
        validateSourceForm(
          const SourceFormValues(
            kind: SourceKind.m3uUrl,
            url: 'http://other.example/get.php?username=***&password=***',
            savedMaskedUrl: masked,
          ),
        ),
        {SourceField.url: SourceFieldError.maskedUrl},
      );
    });

    test('M3U file: a file is required', () {
      expect(
        validateSourceForm(const SourceFormValues(kind: SourceKind.m3uFile)),
        {SourceField.file: SourceFieldError.required},
      );
      expect(
        validateSourceForm(
          const SourceFormValues(kind: SourceKind.m3uFile, hasFile: true),
        ),
        isEmpty,
      );
    });

    test('Xtream: server, username and password, in display order', () {
      final errors = validateSourceForm(
        const SourceFormValues(kind: SourceKind.xtream, username: '  '),
      );
      expect(errors, {
        SourceField.server: SourceFieldError.required,
        SourceField.username: SourceFieldError.required,
        SourceField.password: SourceFieldError.required,
      });
      expect(errors.keys.first, SourceField.server);

      expect(
        validateSourceForm(
          const SourceFormValues(
            kind: SourceKind.xtream,
            server: 'bad host:99999',
            username: 'u',
            password: 'p',
          ),
        ),
        {SourceField.server: SourceFieldError.invalidUrl},
      );
      // The scheme may be left out.
      expect(
        validateSourceForm(
          const SourceFormValues(
            kind: SourceKind.xtream,
            server: 'panel.example.com:8080',
            username: 'u',
            password: 'p',
          ),
        ),
        isEmpty,
      );
    });

    test('Xtream: editing keeps the saved password when left empty', () {
      expect(
        validateSourceForm(
          const SourceFormValues(
            kind: SourceKind.xtream,
            server: 'http://h',
            username: 'u',
            hasSavedPassword: true,
          ),
        ),
        isEmpty,
      );
    });

    test('advanced: custom User-Agent, Referer and guide URL', () {
      final errors = validateSourceForm(
        const SourceFormValues(
          kind: SourceKind.m3uUrl,
          url: 'http://h/a.m3u',
          userAgentPreset: null,
          referer: 'not a url',
          epgUrl: 'ftp://h/guide.xml',
        ),
      );
      expect(errors, {
        SourceField.userAgent: SourceFieldError.required,
        SourceField.referer: SourceFieldError.invalidUrl,
        SourceField.epgUrl: SourceFieldError.invalidUrl,
      });
      expect(
        validateSourceForm(
          const SourceFormValues(
            kind: SourceKind.m3uUrl,
            url: 'http://h/a.m3u',
            userAgentPreset: null,
            customUserAgent: 'MyBox/1.0',
            referer: 'https://portal.example/',
            epgUrl: 'http://h/guide.xml.gz',
          ),
        ),
        isEmpty,
      );
      // The masked copy of a saved guide URL is fine; an edited one is not.
      const savedEpg = 'http://h/xmltv.php?username=***&password=***';
      expect(
        validateSourceForm(
          const SourceFormValues(
            kind: SourceKind.m3uUrl,
            url: 'http://h/a.m3u',
            epgUrl: savedEpg,
            savedEpgUrl: savedEpg,
          ),
        ),
        isEmpty,
      );
      expect(
        validateSourceForm(
          const SourceFormValues(
            kind: SourceKind.m3uUrl,
            url: 'http://h/a.m3u',
            epgUrl: 'http://x/xmltv.php?username=***',
            savedEpgUrl: savedEpg,
          ),
        ),
        {SourceField.epgUrl: SourceFieldError.maskedUrl},
      );
    });
  });

  group('User-Agent presets', () {
    test('a saved value maps back to its preset', () {
      expect(userAgentPresetFor(null), kDefaultUserAgentPreset);
      expect(userAgentPresetFor(' '), kDefaultUserAgentPreset);
      expect(userAgentPresetFor(kUserAgentPresets['VLC']), 'VLC');
      expect(userAgentPresetFor('Something/1.0'), isNull);
    });

    test('the value saved for a choice', () {
      expect(userAgentFor(kDefaultUserAgentPreset, ''), isNull);
      expect(userAgentFor('Kodi', 'ignored'), kUserAgentPresets['Kodi']);
      expect(userAgentFor(null, '  MyBox/2 '), 'MyBox/2');
      expect(userAgentFor(null, '  '), isNull);
    });
  });
}
