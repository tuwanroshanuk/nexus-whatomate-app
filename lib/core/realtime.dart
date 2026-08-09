import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'session.dart';

class RealtimeEvent {
  RealtimeEvent(this.type, this.payload);
  final String type;
  final Map<String, dynamic> payload;
}

class RealtimeService extends ChangeNotifier {
  RealtimeService(this.api, this.session);
  final WhatomateApi api;
  final SessionController session;

  final _events = StreamController<RealtimeEvent>.broadcast();
  Stream<RealtimeEvent> get events => _events.stream;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _ping;
  Timer? _retry;
  int _attempt = 0;
  bool _closing = false;
  bool connected = false;
  String? currentContactId;

  Future<void> connect() async {
    if (!session.authenticated || connected || _channel != null) return;
    _closing = false;
    try {
      final token = await session.websocketToken();
      if (token == null || token.isEmpty) throw StateError('No WebSocket token');
      final root = Uri.parse(api.serverRoot);
      final uri = root.replace(
        scheme: root.scheme == 'https' ? 'wss' : 'ws',
        path: '${root.path.endsWith('/') ? root.path.substring(0, root.path.length - 1) : root.path}/ws',
        query: null,
      );
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready;
      channel.sink.add(jsonEncode({'type': 'auth', 'payload': {'token': token}}));
      _subscription = channel.stream.listen(_handle,
          onError: (_) => _lost(), onDone: _lost, cancelOnError: true);
      connected = true;
      _attempt = 0;
      _startPing();
      notifyListeners();
      if (currentContactId != null) setCurrentContact(currentContactId);
    } catch (_) {
      _channel = null;
      connected = false;
      notifyListeners();
      _scheduleRetry();
    }
  }

  void _handle(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;
      final type = decoded['type']?.toString() ?? '';
      final rawPayload = decoded['payload'];
      final payload = rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : <String, dynamic>{'value': rawPayload};
      if (type == 'pong') return;
      _events.add(RealtimeEvent(type, payload));
    } catch (_) {}
  }

  void setCurrentContact(String? contactId) {
    currentContactId = contactId;
    final channel = _channel;
    if (channel != null && connected) {
      channel.sink.add(jsonEncode({'type': 'set_contact', 'payload': {'contact_id': contactId}}));
    }
  }

  void _startPing() {
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(seconds: 25), (_) {
      if (connected) _channel?.sink.add(jsonEncode({'type': 'ping', 'payload': {}}));
    });
  }

  void _lost() {
    _subscription?.cancel();
    _subscription = null;
    _ping?.cancel();
    _channel = null;
    if (connected) {
      connected = false;
      notifyListeners();
    }
    if (!_closing) _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_closing || !session.authenticated || _retry?.isActive == true) return;
    final seconds = min(30, pow(2, min(_attempt, 5)).toInt());
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), connect);
  }

  Future<void> disconnect() async {
    _closing = true;
    _retry?.cancel();
    _ping?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    connected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _events.close();
    super.dispose();
  }
}
