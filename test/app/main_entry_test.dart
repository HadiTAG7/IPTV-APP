import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/main.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';

void main() {
  const token = 'abcdefghijklmnopqrstuvwxyz0123456789-_ABCDE';

  Future<List<String>> run(List<String> args) async {
    final ran = <String>[];
    await startApp(
      args,
      app: () async => ran.add('app'),
      viewer: (a) async => ran.add('viewer ${a.port} ${a.locale}'),
      onInvalid: () async => ran.add('invalid'),
    );
    return ran;
  }

  test('no arguments, or other ones: the app', () async {
    expect(await run(const []), ['app']);
    expect(await run(const ['--port=5000', '--token=$token']), ['app']);
  });

  test('the viewer flag: the light viewer, never the app', () async {
    final args = const ViewerLaunchArgs(
      port: 50123,
      token: token,
      locale: 'ar',
    ).toArgs();
    expect(await run(args), ['viewer 50123 ar']);
  });

  test('a broken viewer line ends the process, never starts the app', () async {
    expect(await run(const ['--viewer']), ['invalid']);
    expect(await run(const ['--viewer', '--port=1', '--token=short']), [
      'invalid',
    ]);
  });
}
