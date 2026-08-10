import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'realtime.dart';
import 'session.dart';

class NativeCallAction {
  const NativeCallAction({required this.action, required this.payload});
  final String action;
  final Map<String, dynamic> payload;
}

class PushBridge extends ChangeNotifier {
  PushBridge(this.session, this.realtime);

  final SessionController session;
  final RealtimeService realtime;

  static const _channel = MethodChannel('uk.nexuscloud.whatomate/push');
  static const _events = EventChannel('uk.nexuscloud.whatomate/push-events');

  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const applicationId = String.fromEnvironment('FIREBASE_APP_ID');
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');

  final _callActions = StreamController<NativeCallAction>.broadcast();
  Stream<NativeCallAction> get callActions => _callActions.stream;

  StreamSubscription<dynamic>? _nativeEvents;
  bool configured = false;
  String? token;
  String? lastError;

  bool get supported => !kIsWeb && Platform.isAndroid;
  bool get hasFirebaseConfig =>
      projectId.isNotEmpty && applicationId.isNotEmpty && apiKey.isNotEmpty && senderId.isNotEmpty;

  Future<void> initialize() async {
    if (!supported || !session.authenticated || !hasFirebaseConfig) return;
    try {
      _nativeEvents ??= _events.receiveBroadcastStream().listen(_handleNativeEvent);
      final result = await _channel.invokeMapMethod<String, dynamic>('configure', {
        'projectId': projectId,
        'applicationId': applicationId,
        'apiKey': apiKey,
        'senderId': senderId,
      });
      token = result?['token']?.toString();
      configured = result?['configured'] == true;
      if (token != null && token!.isNotEmpty) {
        // registerPushToken waits for the server's authenticated
        // push_registered acknowledgement, so configured=true alone never
        // falsely implies that this installation is call-reachable.
        await realtime.registerPushToken(token!);
      }
      final initial = await _channel.invokeMapMethod<String, dynamic>('getInitialCallAction');
      if (initial != null && initial['action'] != null) _emitAction(initial);
      lastError = null;
    } catch (e) {
      lastError = e.toString();
    }
    notifyListeners();
  }

  Future<void> requestNotificationPermission() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } catch (_) {}
  }

  Future<void> showOngoingCall({required String caller, required String status}) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('showOngoingCall', {
        'caller': caller,
        'status': status,
      });
    } catch (_) {}
  }

  Future<void> cancelOngoingCall() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('cancelOngoingCall');
    } catch (_) {}
  }

  Future<void> backgroundAfterCallAction() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('backgroundAfterCallAction');
    } catch (_) {}
  }

  Future<void> refreshRegistration() async {
    final value = token;
    if (value == null || value.isEmpty || !session.authenticated) return;
    await realtime.registerPushToken(value);
  }

  Future<void> unregister() async {
    final value = token;
    if (value == null || value.isEmpty) return;
    try {
      // Do not require SessionController.authenticated here. Logout clears
      // the Flutter session first, but the already-authenticated WebSocket is
      // deliberately kept alive long enough to remove this device token.
      // Without this, a signed-out phone could remain in team call rotation.
      await realtime.unregisterPushToken(value);
    } catch (_) {}
    token = null;
    configured = false;
    notifyListeners();
  }

  Future<bool> canUseFullScreenIntent() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('canUseFullScreenIntent') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openFullScreenIntentSettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('openFullScreenIntentSettings');
    } catch (_) {}
  }

  void _handleNativeEvent(dynamic raw) {
    if (raw is Map) _emitAction(Map<String, dynamic>.from(raw));
  }

  void _emitAction(Map<String, dynamic> raw) {
    final action = raw['action']?.toString();
    if (action == null || action.isEmpty) return;
    final rawPayload = raw['payload'];
    final payload = rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : <String, dynamic>{};
    _callActions.add(NativeCallAction(action: action, payload: payload));
  }

  @override
  void dispose() {
    _nativeEvents?.cancel();
    _callActions.close();
    super.dispose();
  }
}
