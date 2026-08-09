import 'dart:async';

import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/calling.dart';
import 'core/push_bridge.dart';
import 'core/realtime.dart';
import 'core/session.dart';
import 'ui/root.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await WhatomateApi.create();
  final session = SessionController(api);
  await session.bootstrap();
  final realtime = RealtimeService(api, session);
  final calls = CallingService(api, realtime);
  final push = PushBridge(api, session);
  final coordinator = NativeCallCoordinator(api, session, calls, push);
  await coordinator.start();
  if (session.authenticated) {
    await realtime.connect();
    await push.initialize();
    await push.requestNotificationPermission();
  }
  session.addListener(() {
    if (session.authenticated) {
      unawaited(realtime.connect());
      unawaited(push.initialize());
    } else {
      unawaited(realtime.disconnect());
    }
  });
  runApp(WhatomateRoot(api: api, session: session, realtime: realtime, calls: calls));
}

class NativeCallCoordinator {
  NativeCallCoordinator(this.api, this.session, this.calls, this.push);

  final WhatomateApi api;
  final SessionController session;
  final CallingService calls;
  final PushBridge push;
  StreamSubscription<NativeCallAction>? _subscription;
  bool _handling = false;

  Future<void> start() async {
    _subscription ??= push.callActions.listen((action) {
      unawaited(_handle(action));
    });
  }

  Future<void> _handle(NativeCallAction action) async {
    if (_handling || !session.authenticated) return;
    _handling = true;
    try {
      final transfer = await _resolveTransfer(action.payload);
      if (transfer == null) return;
      final transferId = transfer['id']?.toString();
      if (transferId == null || transferId.isEmpty) return;

      if (action.action == 'answer') {
        await calls.acceptTransfer(transfer);
      } else if (action.action == 'decline') {
        await api.post('/call-transfers/$transferId/hangup', data: {});
      }
    } catch (_) {
      // The Calls screen and realtime stream will expose the latest server state.
      // A stale native notification may race with another agent accepting a call;
      // in that case the backend correctly returns conflict/not-found and no retry
      // should be attempted from this tap.
    } finally {
      _handling = false;
    }
  }

  Future<Map<String, dynamic>?> _resolveTransfer(Map<String, dynamic> payload) async {
    final transferId = payload['id']?.toString() ?? payload['transfer_id']?.toString();
    if (transferId != null && transferId.isNotEmpty) {
      try {
        final data = api.unwrap(await api.get('/call-transfers/$transferId'));
        if (data is Map) return Map<String, dynamic>.from(data);
      } catch (_) {}
    }

    final callLogId = payload['call_log_id']?.toString();
    final data = api.unwrap(await api.get('/call-transfers', query: {
      'status': 'waiting',
      'page': 1,
      'limit': 50,
    }));
    final raw = data is Map ? data['call_transfers'] : data;
    if (raw is! List) return null;
    final transfers = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e));
    if (callLogId != null && callLogId.isNotEmpty) {
      for (final transfer in transfers) {
        if (transfer['call_log_id']?.toString() == callLogId) return transfer;
      }
    }
    for (final transfer in transfers) {
      return transfer;
    }
    return null;
  }
}
