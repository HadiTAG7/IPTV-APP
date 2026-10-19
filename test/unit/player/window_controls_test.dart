import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/platform/window_controls.dart';
import 'package:iptv_player/core/platform/window_fullscreen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(windowsWindowChannel, null);
    windowsWindowChannel.setMethodCallHandler(null);
  });

  test('Windows: the runner leaving compact by itself is heard', () async {
    final window = WindowControls.native(platform: TargetPlatform.windows);
    expect(window.supportsCompactAndPin, isTrue);
    var heard = 0;
    final sub = window.compactEnded.listen((_) => heard++);
    addTearDown(sub.cancel);
    await messenger.handlePlatformMessage(
      windowsWindowChannel.name,
      windowsWindowChannel.codec.encodeMethodCall(
        const MethodCall('compactEnded'),
      ),
      (_) {},
    );
    expect(heard, 1);
  });

  test('Windows: the runner channel with its arguments', () async {
    final calls = <(String, Object?)>[];
    messenger.setMockMethodCallHandler(windowsWindowChannel, (call) async {
      calls.add((call.method, call.arguments));
      return null;
    });
    final window = WindowControls.native(platform: TargetPlatform.windows);
    await window.setAlwaysOnTop(true);
    await window.setAlwaysOnTop(false);
    await window.setTitle('قناة الأخبار');
    await window.enterCompact();
    await window.exitCompact();
    await window.fullscreen.enter();
    await window.fullscreen.exit();
    expect(calls, [
      ('setAlwaysOnTop', true),
      ('setAlwaysOnTop', false),
      ('setTitle', 'قناة الأخبار'),
      ('enterCompact', null),
      ('exitCompact', null),
      ('enterFullscreen', null),
      ('exitFullscreen', null),
    ]);
  });

  test(
    'without the runner (Linux) nothing throws; reported once each',
    () async {
      final errors = <String>[];
      final window = WindowControls.native(
        platform: TargetPlatform.linux,
        onError: errors.add,
      );
      await window.setAlwaysOnTop(true);
      await window.setAlwaysOnTop(false);
      await window.setTitle('News');
      await window.enterCompact();
      await window.exitCompact();
      expect(errors, [
        'Window setAlwaysOnTop unsupported',
        'Window setTitle unsupported',
        'Window enterCompact unsupported',
        'Window exitCompact unsupported',
      ]);
    },
  );

  test('runner failures are reported, never thrown', () async {
    messenger.setMockMethodCallHandler(windowsWindowChannel, (call) async {
      throw PlatformException(code: 'bad-arguments');
    });
    final errors = <String>[];
    final window = WindowControls.native(
      platform: TargetPlatform.windows,
      onError: errors.add,
    );
    await window.setTitle('News');
    await window.setTitle('News');
    expect(errors, hasLength(2));
    expect(errors.first, contains('setTitle failed'));
  });

  test('long titles are cut, never inside an emoji', () async {
    final titles = <String>[];
    messenger.setMockMethodCallHandler(windowsWindowChannel, (call) async {
      titles.add(call.arguments as String);
      return null;
    });
    final window = WindowControls.native(platform: TargetPlatform.windows);
    await window.setTitle('a' * 300);
    // A surrogate pair straddling the cut.
    await window.setTitle('${'b' * 198}\u{1F3C6}tail');
    expect(titles[0], hasLength(WindowControls.maxTitleLength));
    expect(titles[0], endsWith('…'));
    expect(titles[1], '${'b' * 198}…');
    await window.setTitle('short');
    expect(titles.last, 'short');
  });
}
