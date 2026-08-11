import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import 'calling.dart';

Future<void> initializeDesktopWindow() async {
  if (!Platform.isWindows) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1180, 780),
    minimumSize: Size(860, 620),
    center: true,
    title: 'Nexus One',
    backgroundColor: Colors.white,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

/// Supplies the desktop equivalent of Android's native incoming-call surface.
///
/// Windows receives signaling through the authenticated realtime connection
/// while the standalone app is running. A native desktop notification and a
/// restored/focused app window make the Flutter answer/decline surface visible.
class DesktopCallBridge {
  DesktopCallBridge(this.calls);

  final CallingService calls;
  LocalNotification? _notification;
  String? _incomingId;
  bool _initialized = false;

  Future<void> initialize() async {
    if (!Platform.isWindows || _initialized) return;
    await localNotifier.setup(
      appName: 'Nexus One',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    calls.addListener(_sync);
    _initialized = true;
    _sync();
  }

  void _sync() {
    if (!Platform.isWindows) return;
    final incoming = calls.incomingOffer;
    final id = _transferId(incoming);
    if (incoming == null || calls.state.active) {
      if (_incomingId != null) {
        _incomingId = null;
        _closeNotification();
      }
      return;
    }
    if (id == _incomingId) return;
    _incomingId = id;
    _closeNotification();
    _notification = LocalNotification(
      title: 'Incoming Nexus One call',
      body: '${_caller(incoming)} is calling. Open Nexus One to answer or decline.',
      actions: [
        LocalNotificationAction(text: 'Answer'),
        LocalNotificationAction(text: 'Decline'),
      ],
    )
      ..onClick = () {
        unawaited(_activateWindow());
      }
      ..onClickAction = (index) {
        unawaited(_handleAction(index, incoming));
      };
    unawaited(_notification!.show());
    unawaited(_activateWindow());
  }

  Future<void> _handleAction(int index, Map<String, dynamic> incoming) async {
    try {
      if (index == 0) {
        await _activateWindow();
        await calls.acceptTransfer(incoming);
      } else if (index == 1) {
        await calls.declineTransfer(incoming);
      }
    } catch (_) {
      // The in-app call surface reports authoritative API/media errors. A
      // notification action can race another agent accepting the same call.
      await _activateWindow();
    }
  }

  Future<void> _activateWindow() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAlwaysOnTop(true);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await windowManager.setAlwaysOnTop(false);
  }

  void _closeNotification() {
    final notification = _notification;
    _notification = null;
    if (notification != null) unawaited(notification.close());
  }

  String? _transferId(Map<String, dynamic>? payload) =>
      payload?['id']?.toString() ?? payload?['transfer_id']?.toString();

  String _caller(Map<String, dynamic> payload) {
    final contact = payload['contact'];
    if (contact is Map) {
      final value = contact['profile_name'] ?? contact['name'] ?? contact['phone_number'];
      if (value != null && value.toString().trim().isNotEmpty) return value.toString();
    }
    return (payload['contact_name'] ??
            payload['caller_name'] ??
            payload['caller_phone'] ??
            'A contact')
        .toString();
  }

  void dispose() {
    calls.removeListener(_sync);
    _closeNotification();
  }
}
