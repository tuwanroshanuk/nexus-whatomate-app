import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'api_client.dart';
import 'realtime.dart';

class CallState {
  const CallState({
    this.callLogId,
    this.transferId,
    this.contactId,
    this.contactName = '',
    this.phone = '',
    this.direction = 'outgoing',
    this.status = 'idle',
    this.muted = false,
    this.onHold = false,
    this.seconds = 0,
  });

  final String? callLogId;
  final String? transferId;
  final String? contactId;
  final String contactName;
  final String phone;
  final String direction;
  final String status;
  final bool muted;
  final bool onHold;
  final int seconds;

  bool get active => status != 'idle' && status != 'ended' && status != 'failed';

  CallState copyWith({
    String? callLogId,
    String? transferId,
    String? contactId,
    String? contactName,
    String? phone,
    String? direction,
    String? status,
    bool? muted,
    bool? onHold,
    int? seconds,
  }) => CallState(
        callLogId: callLogId ?? this.callLogId,
        transferId: transferId ?? this.transferId,
        contactId: contactId ?? this.contactId,
        contactName: contactName ?? this.contactName,
        phone: phone ?? this.phone,
        direction: direction ?? this.direction,
        status: status ?? this.status,
        muted: muted ?? this.muted,
        onHold: onHold ?? this.onHold,
        seconds: seconds ?? this.seconds,
      );
}

class CallingService extends ChangeNotifier {
  CallingService(this.api, this.realtime) {
    _ws = realtime.events.listen(_onEvent);
  }
  final WhatomateApi api;
  final RealtimeService realtime;
  late final StreamSubscription<RealtimeEvent> _ws;

  CallState state = const CallState();
  MediaStream? _localStream;
  RTCPeerConnection? _peer;
  Timer? _duration;
  Map<String, dynamic>? incomingOffer;

  Future<List<Map<String, dynamic>>> _iceServers() async {
    final response = await api.get('/calls/ice-servers');
    final data = api.unwrap(response);
    final raw = data is Map ? data['ice_servers'] : null;
    if (raw is! List) return [];
    return raw.whereType<Map>().map((entry) => {
      'urls': entry['urls'],
      if (entry['username'] != null) 'username': entry['username'],
      if (entry['credential'] != null) 'credential': entry['credential'],
    }).toList();
  }

  Future<RTCPeerConnection> _newPeer() async {
    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    final peer = await createPeerConnection({
      'iceServers': await _iceServers(),
      'sdpSemantics': 'unified-plan',
    });
    for (final track in _localStream!.getAudioTracks()) {
      await peer.addTrack(track, _localStream!);
    }
    peer.onConnectionState = (value) {
      if (value == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          value == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _cleanup(status: 'ended');
      }
    };
    _peer = peer;
    return peer;
  }

  Future<String> _createOffer(RTCPeerConnection peer) async {
    final offer = await peer.createOffer({'offerToReceiveAudio': true});
    await peer.setLocalDescription(offer);
    await _waitForIce(peer);
    final local = await peer.getLocalDescription();
    if (local?.sdp == null) throw ApiException('Unable to create audio session');
    return local!.sdp!;
  }

  Future<void> _waitForIce(RTCPeerConnection peer) async {
    if (peer.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) return;
    final completer = Completer<void>();
    Timer? timeout;
    peer.onIceGatheringState = (value) {
      if (value == RTCIceGatheringState.RTCIceGatheringStateComplete && !completer.isCompleted) {
        timeout?.cancel();
        completer.complete();
      }
    };
    timeout = Timer(const Duration(seconds: 4), () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
  }

  Future<void> makeOutgoingCall({
    required String contactId,
    required String contactName,
    required String whatsappAccount,
    String phone = '',
  }) async {
    if (state.active) throw ApiException('Another call is already active');
    state = CallState(contactId: contactId, contactName: contactName, phone: phone, status: 'initiating');
    notifyListeners();
    try {
      final peer = await _newPeer();
      final offer = await _createOffer(peer);
      final response = await api.post('/calls/outgoing', data: {
        'contact_id': contactId,
        'whatsapp_account': whatsappAccount,
        'sdp_offer': offer,
      });
      final data = api.unwrap(response);
      if (data is! Map) throw ApiException('Invalid call response');
      final answer = data['sdp_answer']?.toString();
      if (answer == null || answer.isEmpty) throw ApiException('Call answer was missing');
      await peer.setRemoteDescription(RTCSessionDescription(answer, 'answer'));
      state = state.copyWith(callLogId: data['call_log_id']?.toString(), status: 'ringing');
      _startTimer();
      notifyListeners();
    } catch (_) {
      _cleanup(status: 'failed');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> callPermission(String contactId, String account) async {
    final response = await api.get('/calls/permission/$contactId', query: {'account': account});
    final data = api.unwrap(response);
    return data is Map ? Map<String, dynamic>.from(data) : {};
  }

  Future<void> requestPermission(String contactId, String account, {String method = 'interactive'}) async {
    await api.post('/calls/request-permission', data: {
      'contact_id': contactId,
      'whatsapp_account': account,
      'method': method,
    });
  }

  Future<void> acceptTransfer(Map<String, dynamic> transfer) async {
    if (state.active) throw ApiException('Another call is already active');
    final id = transfer['id']?.toString();
    if (id == null) throw ApiException('Transfer ID is missing');
    state = CallState(
      transferId: id,
      callLogId: transfer['call_log_id']?.toString(),
      contactId: transfer['contact_id']?.toString(),
      contactName: (transfer['contact']?['profile_name'] ?? transfer['caller_phone'] ?? 'Incoming call').toString(),
      phone: (transfer['caller_phone'] ?? '').toString(),
      direction: 'incoming',
      status: 'connecting',
    );
    notifyListeners();
    try {
      final peer = await _newPeer();
      final offer = await _createOffer(peer);
      final response = await api.post('/call-transfers/$id/connect', data: {'sdp_offer': offer});
      final data = api.unwrap(response);
      final answer = data is Map ? data['sdp_answer']?.toString() : null;
      if (answer == null || answer.isEmpty) throw ApiException('Transfer answer was missing');
      await peer.setRemoteDescription(RTCSessionDescription(answer, 'answer'));
      state = state.copyWith(status: 'answered');
      _startTimer();
      notifyListeners();
    } catch (_) {
      _cleanup(status: 'failed');
      rethrow;
    }
  }

  Future<void> toggleMute() async {
    final tracks = _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    final next = !state.muted;
    tracks.first.enabled = !next;
    state = state.copyWith(muted: next);
    notifyListeners();
  }

  Future<void> setSpeaker(bool enabled) async {
    await Helper.setSpeakerphoneOn(enabled);
  }

  Future<void> hold() async {
    final id = state.callLogId;
    if (id == null) return;
    await api.post('/call-logs/$id/hold', data: {});
    state = state.copyWith(onHold: true);
    notifyListeners();
  }

  Future<void> resume() async {
    final id = state.callLogId;
    if (id == null) return;
    await api.post('/call-logs/$id/resume', data: {});
    state = state.copyWith(onHold: false);
    notifyListeners();
  }

  Future<void> transfer(String teamId, {String? agentId}) async {
    final id = state.callLogId;
    if (id == null) throw ApiException('No active call');
    await api.post('/call-transfers/initiate', data: {
      'call_log_id': id,
      'team_id': teamId,
      if (agentId != null) 'agent_id': agentId,
    });
    _cleanup(status: 'ended');
  }

  Future<void> hangup() async {
    try {
      if (state.transferId != null) {
        await api.post('/call-transfers/${state.transferId}/hangup', data: {});
      } else if (state.callLogId != null) {
        await api.post('/calls/outgoing/${state.callLogId}/hangup', data: {});
      }
    } finally {
      _cleanup(status: 'ended');
    }
  }

  void _onEvent(RealtimeEvent event) {
    switch (event.type) {
      case 'call_incoming':
        incomingOffer = event.payload;
        notifyListeners();
        break;
      case 'call_transfer_waiting':
        incomingOffer = event.payload;
        notifyListeners();
        break;
      case 'outgoing_call_ringing':
        if (state.active) { state = state.copyWith(status: 'ringing'); notifyListeners(); }
        break;
      case 'outgoing_call_answered':
      case 'call_answered':
        if (state.active) { state = state.copyWith(status: 'answered'); notifyListeners(); }
        break;
      case 'outgoing_call_rejected':
        if (state.active) _cleanup(status: 'ended');
        break;
      case 'outgoing_call_ended':
      case 'call_ended':
        if (state.active) _cleanup(status: 'ended');
        incomingOffer = null;
        notifyListeners();
        break;
      case 'call_transfer_connected':
        incomingOffer = null;
        notifyListeners();
        break;
    }
  }

  void _startTimer() {
    _duration?.cancel();
    _duration = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(seconds: state.seconds + 1);
      notifyListeners();
    });
  }

  Future<void> _cleanup({required String status}) async {
    _duration?.cancel();
    _duration = null;
    final peer = _peer;
    _peer = null;
    if (peer != null) await peer.close();
    final stream = _localStream;
    _localStream = null;
    for (final track in stream?.getTracks() ?? const <MediaStreamTrack>[]) {
      track.stop();
    }
    state = state.copyWith(status: status);
    notifyListeners();
  }

  @override
  void dispose() {
    _ws.cancel();
    _cleanup(status: 'ended');
    super.dispose();
  }
}
