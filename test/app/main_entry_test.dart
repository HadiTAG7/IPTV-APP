import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/main.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';

void main() {
  const token = 'abcdefghijklmnopqrstuvwxyz0123456789-_ABCDE';
  const env = {kViewerTokenEnvironment: token};

  Future<List<String>> run(
    List<String> args, {
    Map<String, String> environment = const {},
  }) async {
    final ran = <String>[];
    await startApp(
      args,
      environment: environment,
      app: () async => ran.add('app'),
      viewer: (a) async => ran.add('viewer ${a.port} ${a.locale} ${a.token}'),
      onInvalid: () async => ran.add('invalid'),
    );
    return ran;
  }

  test('no arguments, or other ones: the app', () async {
    expect(await run(const []), ['app']);
    expect(await run(const ['--port=5000'], environment: env), ['app']);
  });

  test('the viewer flag: the light viewer with the token from the '
      'environment, never the app', () async {
    const args = ViewerLaunchArgs(port: 50123, token: token, locale: 'ar');
    expect(await run(args.toArgs(), environment: args.environment), [
      'viewer 50123 ar $token',
    ]);
  });

  test(
    'a broken viewer start ends the process, never starts the app',
    () async {
      expect(await run(const ['--viewer'], environment: env), ['invalid']);
      // No token in the environment (one on the command line is not read).
      expect(await run(const ['--viewer', '--port=1', '--token=$token']), [
        'invalid',
      ]);
      expect(
        await run(
          const ['--viewer', '--port=1'],
          environment: const {kViewerTokenEnvironment: 'short'},
        ),
        ['invalid'],
      );
    },
  );
}
