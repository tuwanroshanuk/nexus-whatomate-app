import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/calling.dart';
import '../core/data_repository.dart';
import '../core/realtime.dart';

class EnhancedCallsScreen extends StatefulWidget {
  const EnhancedCallsScreen({
    super.key,
    required this.repo,
    required this.calls,
    required this.realtime,
  });
  final DataRepository repo;
  final CallingService calls;
  final RealtimeService realtime;

  @override
  State<EnhancedCallsScreen> createState() => _EnhancedCallsScreenState();
}

class _EnhancedCallsScreenState extends State<EnhancedCallsScreen> {
  final search = TextEditingController();
  List<Map<String, dynamic>> logs = [];
  List<Map<String, dynamic>> waiting = [];
  List<Map<String, dynamic>> accounts = [];
  bool loading = true;
  String status = 'all';
  String direction = 'all';
  String account = 'all';
  Timer? debounce;
  StreamSubscription<RealtimeEvent>? ws;

  @override
  void initState() {
    super.initState();
    load();
    ws = widget.realtime.events.listen((e) {
      if (e.type.startsWith('call_') || e.type.startsWith('outgoing_call_')) load(silent: true);
    });
  }

  @override
  void dispose() {
    search.dispose();
    debounce?.cancel();
    ws?.cancel();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent && mounted) setState(() => loading = true);
    try {
      final response = await widget.repo.api.get('/call-logs', query: {
        'page': 1,
        'limit': 100,
        if (search.text.trim().isNotEmpty) 'phone': search.text.trim(),
        if (status != 'all') 'status': status,
        if (direction != 'all') 'direction': direction,
        if (account != 'all') 'account': account,
      });
      final data = widget.repo.api.unwrap(response);
      final raw = data is Map ? (data['call_logs'] ?? data['items']) : data;
      logs = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
      final futures = await Future.wait([widget.repo.waitingCallTransfers(), widget.repo.accounts()]);
      waiting = futures[0];
      accounts = futures[1];
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _accept(Map<String, dynamic> transfer) async {
    try {
      await widget.calls.acceptTransfer(transfer);
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  Future<void> _decline(Map<String, dynamic> transfer) async {
    try {
      await widget.calls.declineTransfer(transfer);
      await load(silent: true);
      if (mounted) _snack('Declined — routing to the next available agent');
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Clear finished call history?'),
      content: const Text('Active calls are preserved. Finished, missed, rejected and failed entries will be cleared.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
      ],
    ));
    if (ok != true) return;
    try {
      final count = await widget.repo.clearCallHistory();
      await load(silent: true);
      if (mounted) _snack('Cleared $count call record(s)');
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  Future<void> _openDetail(Map<String, dynamic> summary) async {
    Map<String, dynamic> detail = summary;
    List<Map<String, dynamic>> transfers = [];
    try {
      final raw = widget.repo.api.unwrap(await widget.repo.api.get('/call-logs/${summary['id']}'));
      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        if (map['call_log'] is Map) detail = Map<String, dynamic>.from(map['call_log'] as Map);
        if (map['transfers'] is List) {
          transfers = (map['transfers'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .75,
        maxChildSize: .95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(_caller(detail), style: Theme.of(ctx).textTheme.headlineSmall),
            Text(detail['caller_phone']?.toString() ?? ''),
            const SizedBox(height: 12),
            _line('Direction', detail['direction']),
            _line('Status', detail['status']),
            _line('Duration', _duration(_asInt(detail['duration']))),
            _line('Agent', detail['agent'] is Map ? detail['agent']['full_name'] : detail['agent_name']),
            _line('Disconnected by', detail['disconnected_by']),
            _line('WhatsApp account', detail['whatsapp_account']),
            _line('IVR flow', detail['ivr_flow'] is Map ? detail['ivr_flow']['name'] : detail['ivr_flow_name']),
            _line('Started', _date(detail['started_at'] ?? detail['created_at'])),
            if (detail['recording_s3_key'] != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _openRecording(detail['id']?.toString()),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Play recording'),
              ),
            ],
            if (transfers.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Transfer path', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 6),
              for (final transfer in transfers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone_forwarded_outlined),
                  title: Text((transfer['agent_name'] ?? transfer['team_name'] ?? transfer['status'] ?? 'Transfer').toString()),
                  subtitle: Text('${transfer['status'] ?? ''} • ${_date(transfer['created_at'])}'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openRecording(String? id) async {
    if (id == null || id.isEmpty) return;
    try {
      final raw = widget.repo.api.unwrap(await widget.repo.api.get('/call-logs/$id/recording'));
      final url = raw is Map ? (raw['url'] ?? raw['recording_url'])?.toString() : null;
      if (url == null || url.isEmpty) throw StateError('Recording URL is unavailable');
      final uri = Uri.tryParse(url);
      if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Unable to open recording');
      }
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  Widget _line(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 130, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(value?.toString().isNotEmpty == true ? value.toString() : '—')),
    ]),
  );

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Calls'),
      actions: [
        IconButton(tooltip: 'Clear finished history', onPressed: _clearHistory, icon: const Icon(Icons.delete_sweep_outlined)),
        IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    controller: search,
                    onChanged: (_) {
                      debounce?.cancel();
                      debounce = Timer(const Duration(milliseconds: 300), load);
                    },
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search phone number'),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(children: [
                    _filter('Status', status, const ['all', 'completed', 'missed', 'ringing', 'answered', 'rejected', 'failed', 'transferring', 'initiating'], (v) { status = v; load(); }),
                    const SizedBox(width: 8),
                    _filter('Direction', direction, const ['all', 'incoming', 'outgoing'], (v) { direction = v; load(); }),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: account,
                      items: [const DropdownMenuItem(value: 'all', child: Text('All accounts')), ...accounts.map((a) => DropdownMenuItem(value: a['name']?.toString(), child: Text(a['name']?.toString() ?? 'Account')))],
                      onChanged: (v) { if (v != null) { account = v; load(); } },
                    ),
                  ]),
                ),
                if (waiting.isNotEmpty) ...[
                  const _Header('Incoming / waiting'),
                  for (final t in waiting)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.phone_in_talk)),
                      title: Text((t['contact']?['profile_name'] ?? t['caller_phone'] ?? 'Incoming call').toString()),
                      subtitle: Text((t['caller_phone'] ?? '').toString()),
                      trailing: Wrap(spacing: 6, children: [
                        FilledButton(onPressed: () => _accept(t), child: const Text('Answer')),
                        FilledButton.tonal(onPressed: () => _decline(t), child: const Text('Decline')),
                      ]),
                    ),
                  const Divider(),
                ],
                const _Header('Call history'),
                if (logs.isEmpty) const Padding(padding: EdgeInsets.all(36), child: Center(child: Text('No call logs'))),
                for (final log in logs)
                  ListTile(
                    leading: Icon(_icon(log)),
                    title: Text(_caller(log)),
                    subtitle: Text('${log['direction'] ?? ''} • ${log['status'] ?? ''} • ${_duration(_asInt(log['duration']))}'),
                    trailing: Text(_date(log['started_at'] ?? log['created_at']), textAlign: TextAlign.end),
                    onTap: () => _openDetail(log),
                  ),
              ],
            ),
          ),
  );

  Widget _filter(String label, String value, List<String> values, ValueChanged<String> changed) => DropdownButton<String>(
    value: value,
    hint: Text(label),
    items: values.map((v) => DropdownMenuItem(value: v, child: Text(v == 'all' ? 'All $label' : v))).toList(),
    onChanged: (v) { if (v != null) changed(v); },
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
  );
}

String _caller(Map<String, dynamic> log) =>
    (log['contact']?['profile_name'] ?? log['contact_name'] ?? log['caller_phone'] ?? 'Unknown').toString();

IconData _icon(Map<String, dynamic> log) {
  final status = log['status']?.toString();
  if (status == 'missed') return Icons.phone_missed;
  if (status == 'rejected' || status == 'failed') return Icons.phone_disabled_outlined;
  return log['direction'] == 'incoming' ? Icons.phone_in_talk_outlined : Icons.phone_forwarded_outlined;
}

int _asInt(dynamic value) => value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

String _duration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return m > 0 ? '${m}m ${s}s' : '${s}s';
}

String _date(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return '';
  return DateFormat('MMM d\nHH:mm').format(date.toLocal());
}
