import 'dart:async';

import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/calling.dart';
import 'core/push_bridge.dart';
import 'core/realtime.dart';
import 'core/session.dart';
import 'ui/call_surface_host.dart';
import 'ui/root.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await WhatomateApi.create();
  final session = SessionController(api);
  await session.bootstrap();
  final realtime = RealtimeService(api, session);
  final calls = CallingService(api, realtime);
  final push = PushBridge(session, realtime);
  final coordinator = NativeCallCoordinator(api, session, calls, push);
  await coordinator.start();

  Future<void> activateAuthenticatedRuntime() async {
    if (!session.authenticated) return;
    await realtime.connect();
    await push.initialize();
    // Android 13+ requires POST_NOTIFICATIONS at runtime. This must run after
    // a fresh login too, not only when the process starts with a restored
    // session, otherwise FCM can arrive while the call UI remains invisible.
    await push.requestNotificationPermission();
  }

  Future<void> deactivateAuthenticatedRuntime() async {
    // Keep the already-authenticated socket alive until the server has had a
    // chance to remove this installation's FCM token. This prevents a signed-
    // out phone from remaining eligible in IVR/team call rotation.
    await push.unregister();
    await realtime.disconnect();
  }

  if (session.authenticated) {
    await activateAuthenticatedRuntime();
  }
  session.addListener(() {
    if (session.authenticated) {
      unawaited(activateAuthenticatedRuntime());
    } else {
      unawaited(deactivateAuthenticatedRuntime());
    }
  });

  // Mirror the WebRTC call into Android's persistent notification and Telecom
  // lifecycle. Telecom is used for OS-level call coordination/audio routing;
  // the Whatomate backend remains authoritative for signaling and media.
  String nativeCallSignature = '';
  String telecomCallIdentity = '';
  String telecomStatus = '';
  bool telecomOnHold = false;

  void syncNativeCallSurfaces() {
    final state = calls.state;
    if (!state.active) {
      if (nativeCallSignature.isNotEmpty) {
        nativeCallSignature = '';
        unawaited(push.cancelOngoingCall());
      }
      if (telecomCallIdentity.isNotEmpty) {
        telecomCallIdentity = '';
        telecomStatus = '';
        telecomOnHold = false;
        unawaited(push.telecomEndCall());
      }
      return;
    }

    final caller = state.contactName.trim().isNotEmpty
        ? state.contactName.trim()
        : (state.phone.trim().isNotEmpty ? state.phone.trim() : 'Whatomate call');
    final status = state.status.replaceAll('_', ' ');
    final signature = '$caller|$status';
    if (signature != nativeCallSignature) {
      nativeCallSignature = signature;
      unawaited(push.showOngoingCall(caller: caller, status: status));
    }

    final identity = state.callLogId ?? state.transferId ?? '${state.direction}:$caller';
    if (telecomCallIdentity.isEmpty) {
      telecomCallIdentity = identity;
      telecomStatus = state.status;
      telecomOnHold = state.onHold;
      // Incoming calls are registered by the FCM/realtime native call path
      // before the user answers. Outgoing calls originate in Flutter, so they
      // must be introduced to Telecom here.
      if (state.direction == 'outgoing') {
        unawaited(push.reportOutgoingTelecomCall(caller: caller, address: state.phone));
      }
    }

    if (state.status == 'answered' && telecomStatus != 'answered') {
      unawaited(push.telecomSetActive());
    }
    if (state.onHold != telecomOnHold) {
      if (state.onHold) {
        unawaited(push.telecomSetInactive());
      } else {
        unawaited(push.telecomSetActive());
      }
      telecomOnHold = state.onHold;
    }
    telecomStatus = state.status;
  }

  calls.addListener(syncNativeCallSurfaces);
  syncNativeCallSurfaces();

  runApp(
    CallSurfaceHost(
      api: api,
      calls: calls,
      child: WhatomateRoot(
        api: api,
        session: session,
        realtime: realtime,
        calls: calls,
      ),
    ),
  );
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
      if (action.action == 'hangup') {
        if (calls.state.active) await calls.hangup();
        return;
      }
      if (action.action == 'hold') {
        if (calls.state.active && !calls.state.onHold) await calls.hold();
        return;
      }
      if (action.action == 'resume') {
        if (calls.state.active && calls.state.onHold) await calls.resume();
        return;
      }

      final transfer = await _resolveTransfer(action.payload);
      if (transfer == null) return;
      final transferId = transfer['id']?.toString();
      if (transferId == null || transferId.isEmpty) return;

      if (action.action == 'answer') {
        await calls.acceptTransfer(transfer);
      } else if (action.action == 'decline') {
        // Decline is now an authoritative routing decision: the server records
        // this agent as tried and immediately advances the same IVR/team
        // transfer to another eligible agent without ending the caller leg.
        await calls.declineTransfer(transfer);
      }
    } catch (_) {
      // A stale native notification may race with another web/mobile surface
      // accepting the call. The server owns the authoritative transfer state,
      // so this device never retries a failed claim blindly.
    } finally {
      if (action.action == 'decline') {
        await push.backgroundAfterCallAction();
      }
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
