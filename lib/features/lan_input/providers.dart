import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/net/lan_input_server.dart';

export '../../core/net/lan_input_server.dart'
    show
        LanForm,
        LanInputServer,
        LanInputStatus,
        LanNoNetworkException,
        LanSubmission,
        LanSubmissionKind;

/// Starts a phone-input server for [form].
typedef LanServerStarter = Future<LanInputServer> Function(LanForm form);

/// How "Type on your phone" starts its server: on the device's LAN address
/// in the app; tests bind to the loopback address.
final lanServerStarterProvider = Provider<LanServerStarter>((ref) {
  final log = ref.watch(ringLogProvider);
  return (form) => LanInputServer.start(form: form, log: log);
});
