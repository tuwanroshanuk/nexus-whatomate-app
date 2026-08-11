import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/calling.dart';

/// App-wide call surface that sits above the application's Navigator.
///
/// Chat and management screens are pushed as normal routes, so a call UI that
/// lives inside the tab shell can disappear behind those routes. This host is
/// deliberately mounted above WhatomateRoot so an active call is always
/// reachable regardless of which route is currently open.
class CallSurfaceHost extends StatefulWidget {
  const CallSurfaceHost({
    super.key,
    required this.child,
    required this.calls,
    required this.api,
  });

  final Widget child;
  final CallingService calls;
  final WhatomateApi api;

  @override
  State<CallSurfaceHost> createState() => _CallSurfaceHostState();
}

class _CallSurfaceHostState extends State<CallSurfaceHost>
    with WidgetsBindingObserver {
  bool _expanded = false;
  bool _speaker = false;
  bool _busy = false;
  bool _showTransfer = false;
  bool _loadingTeams = false;
  bool _incomingBusy = false;
  bool _wasActive = false;
  bool _endingFromDetach = false;
  String? _error;
  List<Map<String, dynamic>> _teams = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.calls.addListener(_callChanged);
    _wasActive = widget.calls.state.active;
    _expanded = _wasActive;
  }

  @override
  void didUpdateWidget(covariant CallSurfaceHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.calls != widget.calls) {
      oldWidget.calls.removeListener(_callChanged);
      widget.calls.addListener(_callChanged);
      _wasActive = widget.calls.state.active;
      _expanded = _wasActive;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.calls.removeListener(_callChanged);
    super.dispose();
  }

  void _callChanged() {
    final active = widget.calls.state.active;
    if (active && !_wasActive) {
      _expanded = true;
      _showTransfer = false;
      _error = null;
    } else if (!active && _wasActive) {
      _expanded = false;
      _showTransfer = false;
      _speaker = false;
      _error = null;
    }
    _wasActive = active;
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Home / lock-screen / ordinary backgrounding should NOT drop a VoIP call.
    // When Flutter is actually detached from the Android view/process, request
    // a graceful server hangup. The backend also terminates the WhatsApp leg
    // when its agent WebRTC peer disconnects, so abrupt process death still has
    // a server-side safety net.
    if (state == AppLifecycleState.detached &&
        widget.calls.state.active &&
        !_endingFromDetach) {
      _endingFromDetach = true;
      unawaited(widget.calls.hangup().catchError((_) {}).whenComplete(() {
        _endingFromDetach = false;
      }));
    }
  }

  Future<void> _hangup() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.calls.hangup();
    } catch (e) {
      _error = widget.api.normalize(e).message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _answerIncoming(Map<String, dynamic> transfer) async {
    if (_incomingBusy) return;
    setState(() {
      _incomingBusy = true;
      _error = null;
    });
    try {
      await widget.calls.acceptTransfer(transfer);
    } catch (e) {
      _error = widget.api.normalize(e).message;
    } finally {
      if (mounted) setState(() => _incomingBusy = false);
    }
  }

  Future<void> _declineIncoming(Map<String, dynamic> transfer) async {
    if (_incomingBusy) return;
    setState(() {
      _incomingBusy = true;
      _error = null;
    });
    try {
      await widget.calls.declineTransfer(transfer);
    } catch (e) {
      _error = widget.api.normalize(e).message;
    } finally {
      if (mounted) setState(() => _incomingBusy = false);
    }
  }

  Future<void> _toggleMute() async {
    try {
      await widget.calls.toggleMute();
    } catch (e) {
      if (mounted) setState(() => _error = widget.api.normalize(e).message);
    }
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speaker;
    try {
      await widget.calls.setSpeaker(next);
      if (mounted) setState(() => _speaker = next);
    } catch (e) {
      if (mounted) setState(() => _error = widget.api.normalize(e).message);
    }
  }

  Future<void> _toggleHold() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.calls.state.onHold) {
        await widget.calls.resume();
      } else {
        await widget.calls.hold();
      }
    } catch (e) {
      _error = widget.api.normalize(e).message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openTransfer() async {
    setState(() {
      _showTransfer = true;
      _loadingTeams = true;
      _error = null;
    });
    try {
      final response = await widget.api.get('/teams', query: {
        'page': 1,
        'limit': 100,
      });
      final data = widget.api.unwrap(response);
      dynamic raw = data;
      if (data is Map) raw = data['teams'] ?? data['items'] ?? data['data'];
      if (raw is List) {
        _teams = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
        _teams = const [];
      }
    } catch (e) {
      _error = widget.api.normalize(e).message;
      _teams = const [];
    } finally {
      if (mounted) setState(() => _loadingTeams = false);
    }
  }

  Future<void> _transferTo(Map<String, dynamic> team) async {
    final id = team['id']?.toString();
    if (id == null || id.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.calls.transfer(id);
      _showTransfer = false;
    } catch (e) {
      _error = widget.api.normalize(e).message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.calls.state.active;
    final incoming = widget.calls.incomingOffer;
    final media = MediaQueryData.fromView(View.of(context));
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!active && incoming != null)
          MediaQuery(
            data: media,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Theme(
                data: ThemeData(
                  useMaterial3: true,
                  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0738f9)),
                ),
                child: _IncomingCallScreen(
                  transfer: incoming,
                  busy: _incomingBusy,
                  error: _error,
                  onAnswer: () => _answerIncoming(incoming),
                  onDecline: () => _declineIncoming(incoming),
                ),
              ),
            ),
          ),
        if (active)
          MediaQuery(
            data: media,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Theme(
                data: ThemeData(
                  useMaterial3: true,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xff0738f9),
                  ),
                ),
                child: _expanded
                    ? _ActiveCallScreen(
                        calls: widget.calls,
                        speaker: _speaker,
                        busy: _busy,
                        error: _error,
                        showTransfer: _showTransfer,
                        loadingTeams: _loadingTeams,
                        teams: _teams,
                        onMinimize: () => setState(() {
                          _expanded = false;
                          _showTransfer = false;
                        }),
                        onMute: _toggleMute,
                        onSpeaker: _toggleSpeaker,
                        onHold: _toggleHold,
                        onTransfer: _openTransfer,
                        onCloseTransfer: () =>
                            setState(() => _showTransfer = false),
                        onTransferTo: _transferTo,
                        onHangup: _hangup,
                      )
                    : _MiniCallBar(
                        calls: widget.calls,
                        onExpand: () => setState(() => _expanded = true),
                        onHangup: _hangup,
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

class _IncomingCallScreen extends StatelessWidget {
  const _IncomingCallScreen({
    required this.transfer,
    required this.busy,
    required this.error,
    required this.onAnswer,
    required this.onDecline,
  });

  final Map<String, dynamic> transfer;
  final bool busy;
  final String? error;
  final Future<void> Function() onAnswer;
  final Future<void> Function() onDecline;

  String get caller {
    final contact = transfer['contact'];
    if (contact is Map) {
      final value = contact['profile_name'] ?? contact['name'] ?? contact['phone_number'];
      if (value != null && value.toString().trim().isNotEmpty) return value.toString();
    }
    return (transfer['contact_name'] ??
            transfer['caller_name'] ??
            transfer['caller_phone'] ??
            'Incoming call')
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    final value = caller;
    final initial = value.trim().isEmpty ? '?' : value.trim().characters.first.toUpperCase();
    return Material(
      color: const Color(0xff0738f9),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'INCOMING NEXUS ONE CALL',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 34),
                  CircleAvatar(
                    radius: 62,
                    backgroundColor: const Color(0xffffd4fc),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Color(0xff111111),
                        fontSize: 44,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    value,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (transfer['caller_phone'] ?? 'WhatsApp voice call').toString(),
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  if (error != null && error!.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                  ],
                  const SizedBox(height: 48),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _IncomingAction(
                        icon: Icons.call_end,
                        label: 'Decline',
                        color: Colors.red,
                        onPressed: busy ? null : onDecline,
                      ),
                      const SizedBox(width: 64),
                      _IncomingAction(
                        icon: Icons.call,
                        label: 'Answer',
                        color: const Color(0xff20a35a),
                        onPressed: busy ? null : onAnswer,
                      ),
                    ],
                  ),
                  if (busy) ...[
                    const SizedBox(height: 28),
                    const CircularProgressIndicator(color: Colors.white),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IncomingAction extends StatelessWidget {
  const _IncomingAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 76,
          height: 76,
          child: IconButton(
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: color.withValues(alpha: .45),
              shape: const CircleBorder(),
            ),
            icon: Icon(icon, size: 34),
          ),
        ),
        const SizedBox(height: 9),
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ActiveCallScreen extends StatelessWidget {
  const _ActiveCallScreen({
    required this.calls,
    required this.speaker,
    required this.busy,
    required this.error,
    required this.showTransfer,
    required this.loadingTeams,
    required this.teams,
    required this.onMinimize,
    required this.onMute,
    required this.onSpeaker,
    required this.onHold,
    required this.onTransfer,
    required this.onCloseTransfer,
    required this.onTransferTo,
    required this.onHangup,
  });

  final CallingService calls;
  final bool speaker;
  final bool busy;
  final String? error;
  final bool showTransfer;
  final bool loadingTeams;
  final List<Map<String, dynamic>> teams;
  final VoidCallback onMinimize;
  final Future<void> Function() onMute;
  final Future<void> Function() onSpeaker;
  final Future<void> Function() onHold;
  final Future<void> Function() onTransfer;
  final VoidCallback onCloseTransfer;
  final Future<void> Function(Map<String, dynamic>) onTransferTo;
  final Future<void> Function() onHangup;

  @override
  Widget build(BuildContext context) {
    final s = calls.state;
    final name = s.contactName.trim().isNotEmpty
        ? s.contactName.trim()
        : (s.phone.trim().isNotEmpty ? s.phone.trim() : 'WhatsApp call');
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final status = _friendlyStatus(s.status, s.direction);
    final answered = s.status == 'answered' || s.seconds > 0;

    return Material(
      color: const Color(0xfff8f8ff),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: onMinimize,
                          tooltip: 'Minimize call',
                          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                        ),
                        const Spacer(),
                        Text(
                          s.direction == 'incoming' ? 'INCOMING CALL' : 'WHATSAPP CALL',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const Spacer(),
                    CircleAvatar(
                      radius: 58,
                      backgroundColor: const Color(0xffffd4fc),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Color(0xff0c0c0c),
                          fontWeight: FontWeight.w700,
                          fontSize: 42,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff0c0c0c),
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (s.phone.isNotEmpty && s.phone != name) ...[
                      const SizedBox(height: 5),
                      Text(
                        s.phone,
                        style: const TextStyle(fontSize: 16, color: Color(0xff444444)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      answered ? _duration(s.seconds) : status,
                      style: const TextStyle(
                        color: Color(0xff0738f9),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (answered) ...[
                      const SizedBox(height: 4),
                      Text(status, style: const TextStyle(color: Color(0xff555555))),
                    ],
                    if (s.onHold) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'CALL ON HOLD',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                    if (error != null && error!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    const Spacer(),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 22,
                      runSpacing: 22,
                      children: [
                        _CallControl(
                          icon: s.muted ? Icons.mic_off : Icons.mic,
                          label: s.muted ? 'Unmute' : 'Mute',
                          selected: s.muted,
                          onTap: busy ? null : onMute,
                        ),
                        _CallControl(
                          icon: Icons.volume_up,
                          label: 'Speaker',
                          selected: speaker,
                          onTap: busy ? null : onSpeaker,
                        ),
                        _CallControl(
                          icon: s.onHold ? Icons.play_arrow : Icons.pause,
                          label: s.onHold ? 'Resume' : 'Hold',
                          selected: s.onHold,
                          onTap: busy || s.callLogId == null ? null : onHold,
                        ),
                        _CallControl(
                          icon: Icons.phone_forwarded,
                          label: 'Transfer',
                          selected: false,
                          onTap: busy || s.callLogId == null ? null : onTransfer,
                        ),
                      ],
                    ),
                    const SizedBox(height: 34),
                    SizedBox(
                      width: 82,
                      height: 82,
                      child: FilledButton(
                        onPressed: busy ? null : onHangup,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: const CircleBorder(),
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: busy
                            ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.call_end, size: 36),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('End call', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            if (showTransfer)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0x99000000),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Material(
                      color: Colors.white,
                      child: SafeArea(
                        top: false,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 430),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 18, 8, 10),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Transfer call to team',
                                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    IconButton(onPressed: onCloseTransfer, icon: const Icon(Icons.close)),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              if (loadingTeams)
                                const Expanded(child: Center(child: CircularProgressIndicator()))
                              else if (teams.isEmpty)
                                const Expanded(child: Center(child: Text('No teams available')))
                              else
                                Flexible(
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: teams.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final team = teams[index];
                                      final name = (team['name'] ?? team['title'] ?? 'Team').toString();
                                      final description = (team['description'] ?? '').toString();
                                      return ListTile(
                                        leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
                                        title: Text(name),
                                        subtitle: description.isEmpty ? null : Text(description),
                                        trailing: const Icon(Icons.chevron_right),
                                        enabled: !busy,
                                        onTap: busy ? null : () => onTransferTo(team),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniCallBar extends StatelessWidget {
  const _MiniCallBar({
    required this.calls,
    required this.onExpand,
    required this.onHangup,
  });

  final CallingService calls;
  final VoidCallback onExpand;
  final Future<void> Function() onHangup;

  @override
  Widget build(BuildContext context) {
    final s = calls.state;
    final name = s.contactName.isNotEmpty
        ? s.contactName
        : (s.phone.isNotEmpty ? s.phone : 'Active call');
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Material(
            color: const Color(0xff0c0c0c),
            child: InkWell(
              onTap: onExpand,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
                child: Row(
                  children: [
                    const Icon(Icons.phone_in_talk, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${_friendlyStatus(s.status, s.direction)} • ${_duration(s.seconds)}',
                            style: const TextStyle(color: Color(0xffdddddd), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onHangup,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.call_end),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: Column(
        children: [
          SizedBox(
            width: 62,
            height: 62,
            child: IconButton.filledTonal(
              onPressed: onTap,
              style: IconButton.styleFrom(
                backgroundColor: selected
                    ? const Color(0xff0738f9)
                    : const Color(0xffffd4fc),
                foregroundColor: selected ? Colors.white : const Color(0xff0c0c0c),
              ),
              icon: Icon(icon, size: 27),
            ),
          ),
          const SizedBox(height: 7),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

String _friendlyStatus(String raw, String direction) {
  switch (raw) {
    case 'initiating':
      return direction == 'incoming' ? 'Connecting…' : 'Calling…';
    case 'ringing':
      return 'Ringing…';
    case 'connecting':
      return 'Connecting…';
    case 'answered':
      return 'Connected';
    case 'held':
      return 'On hold';
    case 'reconnecting':
      return 'Reconnecting…';
    case 'ended':
      return 'Call ended';
    case 'failed':
      return 'Call failed';
    default:
      return raw.isEmpty ? 'Call' : raw.replaceAll('_', ' ');
  }
}

String _duration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}
