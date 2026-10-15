@TestOn('!windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Behavioural tests for the CI shell code: build.yml `run:` steps (run in
/// bash the way GitHub runs them), tool/check_apk.sh against fake build-tools,
/// and the JDK helpers in tool/setup_container.sh.

const _workflow = '.github/workflows/build.yml';
const _impellerKey = 'io.flutter.embedding.android.EnableImpeller';

int _indent(String line) => line.length - line.trimLeft().length;

/// The `run:` script of [step] in [job] of build.yml, with the YAML block
/// indentation removed (`|`) or lines joined (`>`).
String _runScript(String job, String step) {
  final lines = File(_workflow).readAsLinesSync();
  var i = lines.indexOf('  $job:');
  expect(i, isNonNegative, reason: 'job $job');
  int? stepIndent;
  for (i++; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    if (_indent(line) <= 2) break;
    if (line.trim() == '- name: $step') {
      stepIndent = _indent(line);
      break;
    }
  }
  if (stepIndent == null) fail('no step "$step" in job $job');
  for (i++; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    if (_indent(line) <= stepIndent) break;
    final match = RegExp(r'^\s*run: ?([|>]?)(.*)$').firstMatch(line);
    if (match == null) continue;
    final style = match[1]!;
    if (style.isEmpty) return '${match[2]!.trim()}\n';
    final keyIndent = _indent(line);
    final body = <String>[];
    for (i++; i < lines.length; i++) {
      final bodyLine = lines[i];
      if (bodyLine.trim().isNotEmpty && _indent(bodyLine) <= keyIndent) break;
      body.add(bodyLine);
    }
    final blockIndent = _indent(body.firstWhere((l) => l.trim().isNotEmpty));
    final text = body.map(
      (l) => l.length >= blockIndent ? l.substring(blockIndent) : '',
    );
    return style == '|'
        ? '${text.join('\n').trimRight()}\n'
        : '${text.where((l) => l.isNotEmpty).join(' ')}\n';
  }
  fail('step "$step" in job $job has no run script');
}

/// Runs [script] with bash the way GitHub Actions does (`-eo pipefail`).
ProcessResult _bash(
  String script, {
  required Directory cwd,
  Map<String, String> env = const {},
}) {
  final file = File('${cwd.path}/.step.sh')..writeAsStringSync(script);
  return Process.runSync(
    'bash',
    ['--noprofile', '--norc', '-eo', 'pipefail', file.path],
    workingDirectory: cwd.path,
    environment: env,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('ci_scripts_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// `key=value` lines written to `$GITHUB_OUTPUT` / `$GITHUB_ENV`.
Map<String, String> _keyValues(File file) => {
  for (final line in file.readAsLinesSync())
    if (line.contains('='))
      line.substring(0, line.indexOf('=')): line.substring(
        line.indexOf('=') + 1,
      ),
};

String _log(ProcessResult result) =>
    'exit ${result.exitCode}\n${result.stdout}\n${result.stderr}';

void _writeExecutable(String path, String content) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
  Process.runSync('chmod', ['+x', path]);
}

bool _hasJava() {
  try {
    return Process.runSync('java', ['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

const _loadPropsJava = r'''
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

// Mirrors android/app/build.gradle.kts: Properties.load from a UTF-8 reader.
public class LoadProps {
  public static void main(String[] args) throws IOException {
    Properties p = new Properties();
    try (Reader r = new InputStreamReader(new FileInputStream(args[0]), StandardCharsets.UTF_8)) {
      p.load(r);
    }
    for (String k : new TreeSet<>(p.stringPropertyNames())) {
      StringBuilder sb = new StringBuilder(k).append(':');
      p.getProperty(k).codePoints().forEach(c -> sb.append(' ').append(c));
      System.out.println(sb);
    }
  }
}
''';

/// Loads [file] with java.util.Properties the way build.gradle.kts does.
Map<String, String> _javaLoadProperties(File file) {
  final source = File('${file.parent.path}/LoadProps.java')
    ..writeAsStringSync(_loadPropsJava);
  final result = Process.runSync('java', [source.path, file.path]);
  expect(result.exitCode, 0, reason: _log(result));
  return {
    for (final line in LineSplitter.split(result.stdout as String))
      if (line.contains(':'))
        line.substring(0, line.indexOf(':')): String.fromCharCodes(
          line
              .substring(line.indexOf(':') + 1)
              .trim()
              .split(' ')
              .where((c) => c.isNotEmpty)
              .map(int.parse),
        ),
  };
}

void main() {
  final hasJava = _hasJava();

  group('build.yml', () {
    test('run scripts take every value from env, never inline expressions', () {
      // `${{ }}` inside run: is spliced into the script before bash parses it.
      final lines = File(_workflow).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final match = RegExp(r'^\s*run: ?([|>]?)(.*)$').firstMatch(lines[i]);
        if (match == null) continue;
        final block = [match[2]!];
        final keyIndent = _indent(lines[i]);
        for (var j = i + 1; j < lines.length; j++) {
          if (lines[j].trim().isNotEmpty && _indent(lines[j]) <= keyIndent) {
            break;
          }
          block.add(lines[j]);
        }
        expect(block.join('\n'), isNot(contains(r'${{')), reason: lines[i]);
      }
    });

    group('Version', () {
      for (final job in ['android', 'windows']) {
        ProcessResult run(
          Directory dir,
          String refType,
          String refName, {
          String? releaseVersion,
        }) => _bash(
          _runScript(job, 'Version'),
          cwd: dir,
          env: {
            'GITHUB_ENV': '${dir.path}/env',
            'GITHUB_REF_TYPE': refType,
            'GITHUB_REF_NAME': refName,
            'BUILD_NUMBER': '7',
            'RELEASE_VERSION': ?releaseVersion,
          },
        );

        test('$job: a manual release builds release_version', () {
          final dir = _tempDir();
          final result = run(
            dir,
            'branch',
            'claude/x',
            releaseVersion: '0.1.0',
          );
          expect(result.exitCode, 0, reason: _log(result));
          expect(_keyValues(File('${dir.path}/env')), {'BUILD_NAME': '0.1.0'});
        });

        test('$job: rejects a release_version that is not a version', () {
          for (final version in ['v0.1.0', '0.1', r'1.2.3$(id)']) {
            final dir = _tempDir();
            final result = run(
              dir,
              'branch',
              'claude/x',
              releaseVersion: version,
            );
            expect(result.exitCode, 1, reason: '$version\n${_log(result)}');
            expect(result.stdout, contains('::error::'), reason: version);
            expect(File('${dir.path}/env').existsSync(), isFalse);
          }
        });

        test('$job: tag v1.2.3-beta.1 builds 1.2.3-beta.1', () {
          final dir = _tempDir();
          final result = run(dir, 'tag', 'v1.2.3-beta.1');
          expect(result.exitCode, 0, reason: _log(result));
          expect(_keyValues(File('${dir.path}/env')), {
            'BUILD_NAME': '1.2.3-beta.1',
          });
        });

        test('$job: branches build 0.0.0-dev', () {
          final dir = _tempDir();
          final result = run(dir, 'branch', 'main');
          expect(result.exitCode, 0, reason: _log(result));
          expect(_keyValues(File('${dir.path}/env')), {
            'BUILD_NAME': '0.0.0-dev',
          });
        });

        test('$job: rejects tags that are not versions', () {
          for (final tag in ['v1.2', 'vnext', r'v1.2.3$(id)', 'v1.2.3 x']) {
            final dir = _tempDir();
            final result = run(dir, 'tag', tag);
            expect(result.exitCode, 1, reason: '$tag\n${_log(result)}');
            expect(result.stdout, contains('::error::'), reason: tag);
            expect(File('${dir.path}/env').existsSync(), isFalse, reason: tag);
          }
        });
      }
    });

    group('Release signing', () {
      late Directory dir;

      setUp(() {
        dir = _tempDir();
        Directory('${dir.path}/android/app').createSync(recursive: true);
      });

      ProcessResult run(String refType, Map<String, String> secrets) => _bash(
        _runScript('android', 'Release signing'),
        cwd: dir,
        env: {
          'GITHUB_OUTPUT': '${dir.path}/output',
          'GITHUB_REF_TYPE': refType,
          'KEYSTORE_BASE64': '',
          'KEYSTORE_PASSWORD': '',
          'KEY_ALIAS': '',
          'KEY_PASSWORD': '',
          ...secrets,
        },
      );

      File keyProperties() => File('${dir.path}/android/key.properties');
      File keystore() => File('${dir.path}/android/app/release.jks');

      // Leading/trailing spaces, backslashes, tab, Properties separators and
      // non-ASCII: the cases Properties.load(InputStream) used to garble.
      const storePassword = ' p\\x#=: !\té كلمة سر ';
      // A literal backslash-u escape must not be decoded.
      const keyPassword =
          r'\ \'
          r'u0041 back\';
      final keystoreBytes = [0, 1, 2, 127, 128, 250, 255];

      Map<String, String> secrets({
        String storePass = storePassword,
        String keyPass = keyPassword,
      }) => {
        'KEYSTORE_BASE64': base64Encode(keystoreBytes),
        'KEYSTORE_PASSWORD': storePass,
        'KEY_ALIAS': 'iptv',
        'KEY_PASSWORD': keyPass,
      };

      test('writes the keystore and an escaped UTF-8 key.properties', () {
        final result = run('tag', secrets(storePass: '$storePassword\n'));
        expect(result.exitCode, 0, reason: _log(result));
        expect(keystore().readAsBytesSync(), keystoreBytes);
        expect(_keyValues(File('${dir.path}/output')), {
          'suffix': '',
          'release': '1',
        });
        expect(keyProperties().readAsLinesSync(), [
          'storeFile=release.jks',
          'storePassword=\\ p\\\\x#=: !\\té كلمة سر ',
          'keyAlias=iptv',
          r'keyPassword=\\ \\'
              r'u0041 back\\',
        ]);
      });

      test('key.properties reads back exactly with java.util.Properties', () {
        final result = run('branch', secrets(storePass: '$storePassword\n'));
        expect(result.exitCode, 0, reason: _log(result));
        expect(_javaLoadProperties(keyProperties()), {
          'keyAlias': 'iptv',
          'keyPassword': keyPassword,
          'storeFile': 'release.jks',
          'storePassword': storePassword,
        });
      }, skip: hasJava ? null : 'needs a JDK on PATH');

      test('rejects multi-line secrets before writing anything', () {
        final result = run('tag', secrets(keyPass: 'first\nsecond'));
        expect(result.exitCode, 1, reason: _log(result));
        expect(
          result.stdout,
          contains('::error::ANDROID_KEY_PASSWORD must be a single line.'),
        );
        expect(keyProperties().existsSync(), isFalse);
        expect(keystore().existsSync(), isFalse);
      });

      test('tag builds fail without the secrets', () {
        final result = run('tag', {});
        expect(result.exitCode, 1, reason: _log(result));
        expect(result.stdout, contains('::error::Release signing secrets'));
        expect(keyProperties().existsSync(), isFalse);
      });

      test('manual releases fail without the secrets', () {
        final result = run('branch', {'RELEASE_VERSION': '0.1.0'});
        expect(result.exitCode, 1, reason: _log(result));
        expect(result.stdout, contains('::error::Release signing secrets'));
        expect(keyProperties().existsSync(), isFalse);
      });

      test('branch builds fall back to debug signing with a warning', () {
        final result = run('branch', {'KEYSTORE_BASE64': 'AAAA'});
        expect(result.exitCode, 0, reason: _log(result));
        expect(result.stdout, contains('::warning::'));
        expect(_keyValues(File('${dir.path}/output')), {
          'suffix': '-debug-signed',
          'release': '0',
        });
        expect(keyProperties().existsSync(), isFalse);
      });
    });

    group('Release certificate pin', () {
      late Directory dir;
      const fingerprint =
          'EF:F3:EB:AE:C4:E3:48:4B:7B:F3:86:1D:EE:A4:8E:16:'
          '32:A4:20:1D:43:A3:FA:7B:C9:79:C6:2C:8E:A7:DA:E9';
      const digest =
          'eff3ebaec4e3484b7bf3861deea48e1632a4201d43a3fa7bc979c62c8ea7dae9';

      setUp(() => dir = _tempDir());

      void writePin(String content) =>
          File('${dir.path}/.github/release-cert.sha256')
            ..createSync(recursive: true)
            ..writeAsStringSync(content);

      ProcessResult run(
        String refType, {
        required String releaseSigned,
        String? releaseVersion,
      }) {
        File('${dir.path}/output').writeAsStringSync('');
        return _bash(
          _runScript('android', 'Release certificate pin'),
          cwd: dir,
          env: {
            'GITHUB_OUTPUT': '${dir.path}/output',
            'GITHUB_REF_TYPE': refType,
            'RELEASE_SIGNED': releaseSigned,
            'RELEASE_VERSION': ?releaseVersion,
          },
        );
      }

      test('manual releases fail when the pin file is missing', () {
        final result = run(
          'branch',
          releaseSigned: '1',
          releaseVersion: '0.1.0',
        );
        expect(result.exitCode, 1, reason: _log(result));
        expect(
          result.stdout,
          contains('::error::.github/release-cert.sha256 is missing'),
        );
      });

      Map<String, String> outputs() => _keyValues(File('${dir.path}/output'));

      test('tag builds fail when the pin file is missing', () {
        final result = run('tag', releaseSigned: '1');
        expect(result.exitCode, 1, reason: _log(result));
        expect(
          result.stdout,
          contains('::error::.github/release-cert.sha256 is missing'),
        );
        expect(outputs(), isEmpty);
      });

      test('tag builds pin the committed fingerprint, normalised', () {
        writePin('$fingerprint\n');
        final result = run('tag', releaseSigned: '1');
        expect(result.exitCode, 0, reason: _log(result));
        expect(outputs(), {'sha256': digest});
      });

      test('a malformed pin file fails instead of being ignored', () {
        writePin('SHA256: $fingerprint\n');
        final result = run('branch', releaseSigned: '1');
        expect(result.exitCode, 1, reason: _log(result));
        expect(result.stdout, contains('::error::'));
        expect(outputs(), isEmpty);
      });

      test('release-signed branch builds warn when the pin is missing', () {
        final result = run('branch', releaseSigned: '1');
        expect(result.exitCode, 0, reason: _log(result));
        expect(result.stdout, contains('::warning::'));
        expect(outputs(), isEmpty);
      });

      test('debug-signed builds skip the pin', () {
        writePin(digest);
        final result = run('branch', releaseSigned: '0');
        expect(result.exitCode, 0, reason: _log(result));
        expect(outputs(), isEmpty);
      });
    });

    group('Impeller-off compat APK', () {
      test('is opt-in and built with -P impellerOff=true', () {
        final workflow = File(_workflow).readAsStringSync();
        expect(workflow, contains('      impeller_off:\n'));
        expect(
          workflow,
          contains(
            "BUILD_COMPAT: \${{ inputs.impeller_off || vars.IMPELLER_COMPAT_APK == 'true' }}",
          ),
        );
        final compat = _runScript('android', 'Build compat APK (Impeller off)');
        expect(compat, contains('-P impellerOff=true'));
        expect(compat, contains('--target-platform android-arm,android-arm64'));
        expect(compat, isNot(contains('--split-per-abi')));
        for (final step in ['Build split APKs', 'Build universal APK']) {
          expect(_runScript('android', step), isNot(contains('impellerOff')));
        }
        expect(
          _runScript('android', 'Collect compat APK'),
          contains('dist/iptv-player-universal-compat.apk'),
        );
        final lines = File(_workflow).readAsLinesSync();
        for (final step in [
          'Build compat APK (Impeller off)',
          'Collect compat APK',
        ]) {
          final at = lines.indexOf('      - name: $step');
          expect(at, isNonNegative, reason: step);
          expect(
            lines[at + 1],
            "        if: env.BUILD_COMPAT == 'true'",
            reason: step,
          );
        }
      });

      ProcessResult checkApks(Directory dir, List<String> apks) {
        _writeExecutable('${dir.path}/tool/check_apk.sh', r'''
echo "$*|${EXPECT_IMPELLER_OFF:-}|${EXPECTED_CERT_SHA256:-}|${REQUIRE_RELEASE_SIGNED:-}" >> calls.txt
''');
        for (final apk in apks) {
          File('${dir.path}/dist/$apk')
            ..createSync(recursive: true)
            ..writeAsStringSync('apk');
        }
        return _bash(
          _runScript('android', 'Check APKs'),
          cwd: dir,
          env: {
            'EXPECT_IMPELLER_OFF': '',
            'EXPECTED_CERT_SHA256': 'abc123',
            'REQUIRE_RELEASE_SIGNED': '1',
          },
        );
      }

      const standard = [
        'iptv-player-universal.apk',
        'iptv-player-armeabi-v7a.apk',
        'iptv-player-arm64-v8a.apk',
      ];

      test('Check APKs verifies the renderer flag of every APK', () {
        final dir = _tempDir();
        final result = checkApks(dir, [
          ...standard,
          'iptv-player-universal-compat.apk',
        ]);
        expect(result.exitCode, 0, reason: _log(result));
        expect(File('${dir.path}/calls.txt').readAsLinesSync(), [
          'dist/iptv-player-universal.apk 90 armeabi-v7a arm64-v8a||abc123|1',
          'dist/iptv-player-armeabi-v7a.apk 90 armeabi-v7a||abc123|1',
          'dist/iptv-player-arm64-v8a.apk 90 arm64-v8a||abc123|1',
          'dist/iptv-player-universal-compat.apk 90 armeabi-v7a arm64-v8a|1|abc123|1',
        ]);
      });

      test('Check APKs skips the compat APK when it was not built', () {
        final dir = _tempDir();
        final result = checkApks(dir, standard);
        expect(result.exitCode, 0, reason: _log(result));
        expect(File('${dir.path}/calls.txt').readAsLinesSync(), hasLength(3));
      });

      test('the release attaches the compat APK only when present', () {
        final release = File(_workflow).readAsStringSync();
        expect(
          release,
          contains(
            '            dist/SHA256SUMS.txt\n'
            r'            ${{ steps.optional.outputs.compat }}'
            '\n          fail_on_unmatched_files: true\n',
          ),
        );
        final script = _runScript('release', 'Optional release files');
        for (final present in [true, false]) {
          final dir = _tempDir();
          File('${dir.path}/output').writeAsStringSync('');
          if (present) {
            File('${dir.path}/dist/iptv-player-universal-compat.apk')
              ..createSync(recursive: true)
              ..writeAsStringSync('apk');
          }
          final result = _bash(
            script,
            cwd: dir,
            env: {'GITHUB_OUTPUT': '${dir.path}/output'},
          );
          expect(result.exitCode, 0, reason: _log(result));
          expect(
            _keyValues(File('${dir.path}/output')),
            present
                ? {'compat': 'dist/iptv-player-universal-compat.apk'}
                : isEmpty,
          );
        }
      });
    });
  });

  group('build.gradle.kts', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    test('reads key.properties as UTF-8', () {
      expect(
        gradle,
        contains(
          'keystorePropertiesFile.reader(Charsets.UTF_8).use { load(it) }',
        ),
      );
      expect(gradle, isNot(contains('keystorePropertiesFile.inputStream()')));
    });

    test('-PimpellerOff=true merges the Impeller opt-out into release', () {
      expect(
        gradle,
        contains('val impellerOff = booleanProperty("impellerOff")'),
      );
      expect(
        gradle,
        contains(
          '    if (impellerOff) {\n'
          '        sourceSets.getByName("release").manifest.srcFile('
          '"src/impellerOff/AndroidManifest.xml")\n'
          '    }\n',
        ),
      );
    });
  });

  group('tool/check_apk.sh', () {
    late Directory dir;
    late Map<String, String> env;

    const badging = '''
package: name='io.example.app' versionCode='1' versionName='0.0.0-dev'
minSdkVersion:'24'
targetSdkVersion:'36'
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
application: label='Example' icon='res/a.xml' banner='res/b.png'
launchable-activity: name='io.example.app.MainActivity'  label='' icon=''
leanback-launchable-activity: name='io.example.app.MainActivity'  label='' icon='' banner=''
feature-group: label=''
  uses-feature-not-required: name='android.hardware.touchscreen'
  uses-feature-not-required: name='android.software.leanback'
native-code: 'arm64-v8a' 'armeabi-v7a'
''';
    const android = 'http://schemas.android.com/apk/res/android';
    const manifest =
        '''
        A: $android:allowBackup(0x01010280)=false
        A: $android:usesCleartextTraffic(0x010104ec)=true
        A: $android:enableOnBackInvokedCallback(0x0101066c)=true
''';
    String impellerMetaData(String value) =>
        '''
          E: meta-data (line=71)
            A: $android:name(0x01010003)="$_impellerKey" (Raw: "$_impellerKey")
            A: $android:value(0x01010024)=$value
''';
    const digest =
        '3c5850a17880e086c0fcbeb33333fee14220894a9e88c7a31998eac27030d0ce';

    setUp(() {
      dir = _tempDir();
      final tools = '${dir.path}/sdk/build-tools/36.0.0';
      _writeExecutable('$tools/aapt2', '''
#!/usr/bin/env bash
case "\$2" in
  badging) cat "${dir.path}/badging.txt" ;;
  xmltree) cat "${dir.path}/xmltree.txt" ;;
esac
''');
      _writeExecutable('$tools/apksigner', '''
#!/usr/bin/env bash
echo "Signer #1 certificate DN: CN=Example Release, O=Example"
echo "Signer #1 certificate SHA-256 digest: $digest"
''');
      File('${dir.path}/badging.txt').writeAsStringSync(badging);
      File('${dir.path}/app.apk').writeAsStringSync('not really an apk');
      env = {
        'ANDROID_HOME': '${dir.path}/sdk',
        'BUILD_TOOLS_VERSION': '36.0.0',
        'EXPECT_IMPELLER_OFF': '',
        'EXPECTED_CERT_SHA256': '',
        'REQUIRE_RELEASE_SIGNED': '',
      };
    });

    ProcessResult check(
      String xmltree, [
      Map<String, String> extra = const {},
    ]) {
      File('${dir.path}/xmltree.txt').writeAsStringSync(xmltree);
      return Process.runSync(
        'bash',
        [
          '${Directory.current.path}/tool/check_apk.sh',
          '${dir.path}/app.apk',
          '1',
          'armeabi-v7a arm64-v8a',
        ],
        environment: {...env, ...extra},
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    }

    test('passes a default APK', () {
      final result = check(manifest);
      expect(result.exitCode, 0, reason: _log(result));
      expect(result.stdout, contains('ok    no EnableImpeller override'));
    });

    test('fails a default APK that turns Impeller off', () {
      final result = check(manifest + impellerMetaData('false'));
      expect(result.exitCode, 1, reason: _log(result));
      expect(result.stdout, contains('FAIL  no EnableImpeller override'));
    });

    test('EXPECT_IMPELLER_OFF=1 requires EnableImpeller=false', () {
      final off = {'EXPECT_IMPELLER_OFF': '1'};
      final compat = check(manifest + impellerMetaData('false'), off);
      expect(compat.exitCode, 0, reason: _log(compat));
      expect(compat.stdout, contains('ok    Impeller off'));

      for (final xmltree in [manifest, manifest + impellerMetaData('true')]) {
        final result = check(xmltree, off);
        expect(result.exitCode, 1, reason: _log(result));
        expect(result.stdout, contains('FAIL  Impeller off'));
      }
    });

    test('compares the signer with EXPECTED_CERT_SHA256', () {
      final upper = digest
          .toUpperCase()
          .replaceAllMapped(RegExp('..'), (m) => '${m[0]}:')
          .replaceFirst(RegExp(r':$'), '');
      final match = check(manifest, {'EXPECTED_CERT_SHA256': upper});
      expect(match.exitCode, 0, reason: _log(match));
      expect(match.stdout, contains('ok    certificate matches'));

      final other = check(manifest, {'EXPECTED_CERT_SHA256': 'ab' * 32});
      expect(other.exitCode, 1, reason: _log(other));
      expect(other.stdout, contains('FAIL  certificate $digest'));
    });
  });

  group('tool/setup_container.sh JDK check', () {
    late Directory dir;

    /// A fake `java` reporting [version] and [home] like
    /// `java -XshowSettings:properties -version`.
    String fakeJava(String binDir, String version, String home) {
      final path = '$binDir/java';
      _writeExecutable(path, '''
#!/usr/bin/env bash
{
  echo "Property settings:"
  echo "    java.home = $home"
  echo "    java.specification.version = $version"
  echo 'openjdk version "$version"'
} >&2
''');
      return path;
    }

    setUp(() {
      dir = _tempDir();
      // Records `flutter config --jdk-dir` calls.
      _writeExecutable('${dir.path}/bin/flutter', '''
#!/usr/bin/env bash
echo "\$*" >> "${dir.path}/flutter.log"
''');
    });

    ProcessResult ensureJdk({
      required String path,
      String javaHome = '',
      String call = 'ensure_jdk',
    }) => Process.runSync(
      '/bin/bash',
      [
        '-c',
        'source "\$1"; $call',
        'setup',
        '${Directory.current.path}/tool/setup_container.sh',
      ],
      environment: {
        'PATH': path,
        'JAVA_HOME': javaHome,
        'SKIP_APT': '1',
        'HOME': dir.path,
      },
      includeParentEnvironment: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    String systemPath(String bin) => '$bin:/usr/bin:/bin';
    File flutterLog() => File('${dir.path}/flutter.log');

    test('sourcing the script does not run the setup', () {
      final result = ensureJdk(path: systemPath('${dir.path}/bin'), call: ':');
      expect(result.exitCode, 0, reason: _log(result));
      expect(result.stdout, isEmpty);
    });

    test('parses legacy and modern Java versions', () {
      for (final (version, major) in [
        ('1.8', '8'),
        ('11', '11'),
        ('17', '17'),
        ('21.0.2', '21'),
      ]) {
        final java = fakeJava('${dir.path}/bin', version, '/opt/jdk');
        final result = ensureJdk(
          path: systemPath('${dir.path}/bin'),
          call: 'java_major $java',
        );
        expect(result.stdout, major, reason: version);
      }
    });

    test('fails clearly without a JDK on PATH', () {
      final empty = Directory('${dir.path}/empty')..createSync();
      final result = ensureJdk(path: empty.path);
      expect(result.exitCode, 1, reason: _log(result));
      expect(result.stderr, contains('error: no Java 17+ on PATH'));
    });

    test('fails clearly when the only JDK is too old', () {
      for (final version in ['1.8', '11']) {
        fakeJava('${dir.path}/bin', version, '/opt/jdk-old');
        final result = ensureJdk(path: systemPath('${dir.path}/bin'));
        expect(result.exitCode, 1, reason: '$version\n${_log(result)}');
        expect(result.stderr, contains('error: no Java 17+ on PATH'));
      }
    });

    test('accepts Java 17+ and leaves Flutter alone', () {
      fakeJava('${dir.path}/bin', '21', '/opt/jdk-21');
      final result = ensureJdk(path: systemPath('${dir.path}/bin'));
      expect(result.exitCode, 0, reason: _log(result));
      expect(result.stdout, contains('Using Java 21 from /opt/jdk-21'));
      expect(flutterLog().existsSync(), isFalse);
    });

    test('points Flutter at the PATH JDK when JAVA_HOME is too old', () {
      fakeJava('${dir.path}/bin', '17', '/opt/jdk-17');
      final oldHome = '${dir.path}/jdk-11';
      fakeJava('$oldHome/bin', '11', oldHome);
      final result = ensureJdk(
        path: systemPath('${dir.path}/bin'),
        javaHome: oldHome,
      );
      expect(result.exitCode, 0, reason: _log(result));
      expect(flutterLog().readAsStringSync(), 'config --jdk-dir /opt/jdk-17\n');
    });

    test('keeps a usable JAVA_HOME', () {
      fakeJava('${dir.path}/bin', '17', '/opt/jdk-17');
      final home = '${dir.path}/jdk-21';
      fakeJava('$home/bin', '21', home);
      final result = ensureJdk(
        path: systemPath('${dir.path}/bin'),
        javaHome: home,
      );
      expect(result.exitCode, 0, reason: _log(result));
      expect(flutterLog().existsSync(), isFalse);
    });
  });
}
