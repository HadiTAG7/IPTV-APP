import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  debugPrint('$VideoPlayerController');
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('spike'))),
    ),
  );
}
