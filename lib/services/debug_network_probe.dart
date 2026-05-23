// File excluded from the offline-guard scan: this is the documented
// debug-only network reachability probe, not a production network call.
// offline-guard:allow
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log_service.dart';

/// Opens a 200 ms TCP probe to a public DNS resolver. We never send or
/// receive payload bytes — we are only proving that the app *could* reach the
/// network, then loudly logging if so. In production builds this is a no-op.
Future<void> runDebugNetworkProbe() async {
  if (!kDebugMode) return;
  try {
    // offline-guard:allow
    final socket = await Socket.connect(
      '1.1.1.1',
      53,
      timeout: const Duration(milliseconds: 200),
    );
    socket.destroy();
    LogService.instance.warn(
      'Network is reachable. The app itself must never make outbound calls. '
      'If you see traffic, it is a regression — run tool/check_offline.dart.',
    );
  } catch (_) {
    // Expected path: offline or unreachable.
  }
}
