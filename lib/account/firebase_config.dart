/// Public client configuration only. Never put an administrator key here.
abstract final class FirebaseConfig {
  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'hadi-iptv-sync-20261031',
  );
  static const apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyApKuU2kMFHgBv6UKJONPBCtN32aqnc1yA',
  );
  static bool get enabled => projectId.isNotEmpty && apiKey.isNotEmpty;
}
