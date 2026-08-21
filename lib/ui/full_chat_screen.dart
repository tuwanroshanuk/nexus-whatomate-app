import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/calling.dart';
import '../core/data_repository.dart';
import '../core/realtime.dart';
import 'branding.dart';

class FullChatScreen extends StatefulWidget {
  const FullChatScreen({
    super.key,
    required this.repo,
    required this.realtime,
    required this.calls,
    required this.contact,
  });

  final DataRepository repo;
  final RealtimeService realtime;
  final CallingService calls;
  final Map<String, dynamic> contact;

  @override
  State<FullChatScreen> createState() => _FullChatScreenState();
}

class _FullChatScreenState extends State<FullChatScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  StreamSubscription<RealtimeEvent>? ws;

  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> accounts = [];
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> transfers = [];
  bool sending = false;
  String? selectedAccount;
  Map<String, dynamic>? replyingTo;
  Map<String, dynamic> callPermission = const {};

  String get contactId => widget.contact['id'].toString();
  String get contactName =>
      (widget.contact['profile_name'] ??
              widget.contact['name'] ??
              widget.contact['phone_number'] ??
              'Unknown')
          .toString();

  @override
  void initState() {
    super.initState();
    selectedAccount = widget.contact['whatsapp_account']?.toString();
    widget.realtime.setCurrentContact(contactId);
    widget.repo.addListener(_cacheChanged);
    ws = widget.realtime.events.listen(_onRealtime);
    _load();
  }

  @override
  void dispose() {
    widget.realtime.setCurrentContact(null);
    widget.repo.removeListener(_cacheChanged);
    ws?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _onRealtime(RealtimeEvent event) {
    final payloadContact =
        event.payload['contact_id']?.toString() ??
        (event.payload['message'] is Map
            ? (event.payload['message'] as Map)['contact_id']?.toString()
            : null);
    if (payloadContact == contactId &&
        (event.type == 'new_message' ||
            event.type == 'status_update' ||
            event.type == 'reaction_update')) {
      _loadMessages(silent: true);
    }
    if (event.type.startsWith('agent_transfer')) {
      _loadTransfers();
    }
  }

  void _cacheChanged() {
    unawaited(_hydrateMessages());
  }

  Future<void> _hydrateMessages() async {
    final cached = await widget.repo.cachedMessages(contactId);
    if (!mounted) return;
    final shouldScroll = _nearBottom;
    setState(() => messages = cached);
    if (shouldScroll) _scrollBottom();
  }

  Future<void> _load() async {
    final cached = await widget.repo.cachedMessages(contactId);
    if (mounted) {
      setState(() {
        messages = cached;
      });
      _scrollBottom();
    }
    unawaited(widget.repo.markRead(contactId).catchError((_) {}));
    try {
      final result = await Future.wait([
        widget.repo.messages(contactId),
        widget.repo.accounts(),
        widget.repo.users(),
        widget.repo.activeAgentTransfers(contactId: contactId),
      ]);
      messages = result[0];
      accounts = result[1];
      users = result[2];
      transfers = result[3];
      _chooseAccount();
      await _loadCallPermission();
      if (mounted) setState(() {});
      _scrollBottom();
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  Future<void> _loadMessages({bool silent = false}) async {
    try {
      final loaded = await widget.repo.messages(
        contactId,
        account: selectedAccount,
      );
      messages = loaded;
      await widget.repo.markRead(contactId).catchError((_) {});
      if (mounted) setState(() {});
      if (!silent || _nearBottom) _scrollBottom();
    } catch (_) {}
  }

  Future<void> _loadTransfers() async {
    try {
      transfers = await widget.repo.activeAgentTransfers(contactId: contactId);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadCallPermission() async {
    final account = selectedAccount;
    if (account == null || account.isEmpty) {
      callPermission = const {};
      return;
    }
    try {
      callPermission = await widget.calls.callPermission(contactId, account);
    } catch (_) {
      callPermission = const {};
    }
  }

  bool get _callAllowed => const {
    'accepted',
    'temporary',
    'permanent',
  }.contains(callPermission['status']?.toString());

  void _chooseAccount() {
    if (selectedAccount != null && selectedAccount!.isNotEmpty) return;
    for (var i = messages.length - 1; i >= 0; i--) {
      final account = messages[i]['whatsapp_account']?.toString();
      if (account != null && account.isNotEmpty) {
        selectedAccount = account;
        return;
      }
    }
    if (accounts.isNotEmpty)
      selectedAccount = accounts.first['name']?.toString();
  }

  bool get _nearBottom {
    if (!scroll.hasClients) return true;
    return scroll.position.maxScrollExtent - scroll.offset < 160;
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendText() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final pending = <String, dynamic>{
      'id': localId,
      'contact_id': contactId,
      'direction': 'outgoing',
      'message_type': 'text',
      'content': {'body': text},
      'status': 'sending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    setState(() {
      sending = true;
      messages.add(pending);
    });
    input.clear();
    _scrollBottom();
    try {
      final message = await widget.repo.sendText(
        contactId,
        text,
        account: selectedAccount,
        replyTo: replyingTo?['id']?.toString(),
      );
      if (mounted)
        setState(() {
          messages.removeWhere((item) => item['id']?.toString() == localId);
          if (!messages.any(
            (item) => item['id']?.toString() == message['id']?.toString(),
          )) {
            messages.add(message);
          }
          replyingTo = null;
        });
      _scrollBottom();
    } catch (e) {
      input.text = text;
      if (mounted) {
        setState(
          () =>
              messages.removeWhere((item) => item['id']?.toString() == localId),
        );
        _snack(widget.repo.api.normalize(e).message);
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _attach() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'mp4',
        'mov',
        'mp3',
        'm4a',
        'ogg',
        'pdf',
        'doc',
        'docx',
      ],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final caption = TextEditingController();
    if (!mounted) return;
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(result!.files.single.name),
        content: TextField(
          controller: caption,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Caption (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (send != true) return;
    setState(() => sending = true);
    try {
      final message = await widget.repo.sendMedia(
        contactId,
        File(path),
        caption: caption.text,
        account: selectedAccount,
      );
      messages.add(message);
      if (mounted) setState(() {});
      _scrollBottom();
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _pickTemplate() async {
    final templates = await widget.repo.templates(account: selectedAccount);
    if (!mounted) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PickerSheet(
        title: 'WhatsApp templates',
        items: templates,
        titleOf: (item) => (item['name'] ?? 'Template').toString(),
        subtitleOf: (item) =>
            (item['body_content'] ?? item['status'] ?? '').toString(),
      ),
    );
    if (selected == null) return;
    final body = (selected['body_content'] ?? '').toString();
    final params = _tokens(body);
    final values = await _collectParams(params);
    if (values == null) return;
    try {
      await widget.repo.sendTemplate(
        contactId,
        selected['name'].toString(),
        templateParams: values,
        account: selectedAccount,
      );
      await _loadMessages();
      if (mounted) _snack('Template sent');
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  Future<void> _pickCanned() async {
    final items = await widget.repo.cannedResponses();
    if (!mounted) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PickerSheet(
        title: 'Canned responses',
        items: items,
        titleOf: (item) =>
            (item['name'] ?? item['shortcut'] ?? 'Response').toString(),
        subtitleOf: (item) => (item['content'] ?? '').toString(),
      ),
    );
    if (selected == null) return;
    final raw = (selected['content'] ?? '').toString();
    final tokenNames = _tokens(raw)
        .where(
          (token) => !const {
            'contact_name',
            'phone_number',
            'agent_name',
            'user_name',
          }.contains(token),
        )
        .toList();
    final values = await _collectParams(tokenNames);
    if (values == null) return;
    var body = _resolveContext(raw);
    for (final entry in values.entries) {
      body = body.replaceAll(
        RegExp('\\{\\{\\s*${RegExp.escape(entry.key)}\\s*\\}\\}'),
        entry.value,
      );
    }

    final buttons = selected['buttons'];
    String type = 'text';
    Map<String, dynamic>? interactive;
    if (buttons is List && buttons.isNotEmpty) {
      final normalized = buttons
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final replyButtons = normalized
          .where((b) => b['type'] == null || b['type'] == 'reply')
          .toList();
      if (replyButtons.length == normalized.length &&
          replyButtons.length <= 10) {
        type = 'interactive';
        interactive = {
          'type': replyButtons.length <= 3 ? 'button' : 'list',
          'body': body,
          'buttons': [
            for (final b in replyButtons)
              {
                'id': b['id']?.toString() ?? '',
                'title': _resolveContext(b['title']?.toString() ?? ''),
              },
          ],
        };
      } else if (normalized.length == 1 && normalized.first['type'] == 'url') {
        type = 'interactive';
        interactive = {
          'type': 'cta_url',
          'body': body,
          'button_text': normalized.first['title']?.toString() ?? 'Open',
          'url': _resolveContext(normalized.first['url']?.toString() ?? ''),
        };
      } else if (normalized.length == 1 &&
          normalized.first['type'] == 'voice_call') {
        type = 'interactive';
        interactive = {
          'type': 'voice_call',
          'body': body,
          'display_text': normalized.first['title']?.toString() ?? 'Call',
          'ttl_minutes': normalized.first['ttl_minutes'] ?? 15,
        };
      } else if (normalized.length == 1 && normalized.first['type'] == 'flow') {
        type = 'interactive';
        interactive = {
          'type': 'flow',
          'body': body,
          'button_text': normalized.first['title']?.toString() ?? 'Open',
          'flow_id': normalized.first['flow_id']?.toString(),
          'first_screen': normalized.first['screen']?.toString(),
        };
      }
    }

    try {
      await widget.repo.sendMessage(
        contactId,
        type: type,
        content: {'body': body},
        account: selectedAccount,
        replyTo: replyingTo?['id']?.toString(),
        interactive: interactive,
      );
      final id = selected['id']?.toString();
      if (id != null) unawaited(widget.repo.recordCannedUse(id));
      replyingTo = null;
      await _loadMessages();
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  String _resolveContext(String value) {
    final replacements = {
      'contact_name': contactName,
      'phone_number': widget.contact['phone_number']?.toString() ?? '',
    };
    var result = value;
    for (final entry in replacements.entries) {
      result = result.replaceAll(
        RegExp('\\{\\{\\s*${entry.key}\\s*\\}\\}'),
        entry.value,
      );
    }
    return result;
  }

  List<String> _tokens(String value) {
    final found = <String>{};
    final regex = RegExp(r'\{\{\s*([\w.-]+)\s*\}\}');
    for (final match in regex.allMatches(value)) {
      final token = match.group(1);
      if (token != null) found.add(token);
    }
    return found.toList();
  }

  Future<Map<String, String>?> _collectParams(List<String> names) async {
    if (names.isEmpty) return <String, String>{};
    final controllers = {
      for (final name in names) name: TextEditingController(),
    };
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Message parameters'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final name in names)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: controllers[name],
                    decoration: InputDecoration(labelText: name),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final values = {
                for (final e in controllers.entries) e.key: e.value.text.trim(),
              };
              if (values.values.any((v) => v.isEmpty)) return;
              Navigator.pop(context, values);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return result;
  }

  Future<void> _assign() async {
    if (!mounted) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Assign conversation')),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Unassigned'),
              onTap: () => Navigator.pop(context, <String, dynamic>{}),
            ),
            for (final user in users.where((u) => u['is_active'] != false))
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text((user['full_name'] ?? user['email']).toString()),
                subtitle: Text((user['email'] ?? '').toString()),
                onTap: () => Navigator.pop(context, user),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    try {
      await widget.repo.assignContact(contactId, selected['id']?.toString());
      _snack(
        selected.isEmpty ? 'Conversation unassigned' : 'Conversation assigned',
      );
    } catch (e) {
      _snack(widget.repo.api.normalize(e).message);
    }
  }

  Future<void> _transferChatbot() async {
    final account = selectedAccount;
    if (account == null || account.isEmpty) {
      _snack('Choose a WhatsApp account first');
      return;
    }
    try {
      if (transfers.isNotEmpty) {
        await widget.repo.resumeAgentTransfer(transfers.first['id'].toString());
        _snack('Chatbot resumed');
      } else {
        await widget.repo.createAgentTransfer(contactId, account);
        _snack('Conversation transferred to agents');
      }
      await _loadTransfers();
    } catch (e) {
      _snack(widget.repo.api.normalize(e).message);
    }
  }

  Future<void> _call() async {
    final account = selectedAccount;
    if (account == null || account.isEmpty) {
      _snack('Choose a WhatsApp account first');
      return;
    }
    try {
      final permission = await widget.calls.callPermission(contactId, account);
      callPermission = permission;
      if (mounted) setState(() {});
      final status = permission['status']?.toString();
      if (!{'accepted', 'temporary', 'permanent'}.contains(status)) {
        if (!mounted) return;
        final request = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Call permission required'),
            content: const Text(
              'Send the WhatsApp call-permission prompt now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Send'),
              ),
            ],
          ),
        );
        if (request == true) {
          await widget.calls.requestPermission(contactId, account);
          callPermission = const {'status': 'pending'};
          if (mounted) setState(() {});
          _snack('Call permission request sent');
        }
        return;
      }
      await widget.calls.makeOutgoingCall(
        contactId: contactId,
        contactName: contactName,
        whatsappAccount: account,
        phone: widget.contact['phone_number']?.toString() ?? '',
      );
    } catch (e) {
      _snack(widget.repo.api.normalize(e).message);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _format(String before, String after) {
    final selection = input.selection;
    final text = input.text;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(0, text.length)
        : text.length;
    final selected = text.substring(start, end);
    final replacement = '$before$selected$after';
    input.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection(
        baseOffset: start + before.length,
        extentOffset: start + before.length + selected.length,
      ),
    );
    setState(() {});
  }

  Future<void> _expandComposer() async {
    final expanded = TextEditingController(text: input.text)
      ..selection = input.selection.isValid
          ? input.selection
          : TextSelection.collapsed(offset: input.text.length);
    final send = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(Icons.close),
            ),
            title: const Text('Compose Message'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Done'),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _FormattingToolbar(
                  controller: expanded,
                  onChanged: () => setState(() {}),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: TextField(
                      controller: expanded,
                      autofocus: true,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: 'Compose your message',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: nexusBlue),
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.check),
                      label: const Text('Use message'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (send == true) {
      input.value = expanded.value;
      setState(() {});
    }
    expanded.dispose();
  }

  Widget _composer() => SafeArea(
    top: false,
    child: Container(
      color: nexusCream.withValues(alpha: .94),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Expand composer',
                onPressed: _expandComposer,
                icon: const Icon(Icons.open_in_full, size: 20),
              ),
              IconButton(
                tooltip: 'Bold',
                onPressed: () => _format('*', '*'),
                icon: const Icon(Icons.format_bold, size: 20),
              ),
              IconButton(
                tooltip: 'Italic',
                onPressed: () => _format('_', '_'),
                icon: const Icon(Icons.format_italic, size: 20),
              ),
              IconButton(
                tooltip: 'Strikethrough',
                onPressed: () => _format('~', '~'),
                icon: const Icon(Icons.format_strikethrough, size: 20),
              ),
              IconButton(
                tooltip: 'Monospace',
                onPressed: () => _format('```', '```'),
                icon: const Icon(Icons.code, size: 20),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.add_circle_outline),
                onSelected: (value) {
                  if (value == 'media') _attach();
                  if (value == 'template') _pickTemplate();
                  if (value == 'canned') _pickCanned();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'media',
                    child: ListTile(
                      leading: Icon(Icons.attach_file),
                      title: Text('Photo, video, audio or document'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'template',
                    child: ListTile(
                      leading: Icon(Icons.description_outlined),
                      title: Text('WhatsApp template'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'canned',
                    child: ListTile(
                      leading: Icon(Icons.quickreply_outlined),
                      title: Text('Canned response'),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: TextField(
                  controller: input,
                  minLines: 1,
                  maxLines: 6,
                  onSubmitted: (_) => _sendText(),
                  decoration: const InputDecoration(
                    hintText: 'Compose your message',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                style: IconButton.styleFrom(foregroundColor: Colors.black),
                onPressed: sending ? null : _sendText,
                icon: sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined, size: 31),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: nexusBlue,
        foregroundColor: Colors.white,
        toolbarHeight: 82,
        titleSpacing: 4,
        title: const NexusWordmark(onBlue: true, compact: true),
        actions: [
          if (accounts.length > 1)
            PopupMenuButton<String>(
              tooltip: 'WhatsApp account',
              icon: const Icon(Icons.sim_card_outlined),
              initialValue: selectedAccount,
              onSelected: (value) async {
                setState(() => selectedAccount = value);
                await _loadCallPermission();
                await _loadMessages();
              },
              itemBuilder: (_) => [
                for (final account in accounts)
                  PopupMenuItem(
                    value: account['name']?.toString(),
                    child: Text(account['name']?.toString() ?? 'Account'),
                  ),
              ],
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'assign':
                  _assign();
                case 'transfer':
                  _transferChatbot();
                case 'info':
                  _showInfo();
                case 'delete_conversation':
                  _deleteConversation();
                case 'delete_contact':
                  _deleteContact();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'assign', child: Text('Assign agent')),
              PopupMenuItem(
                value: 'transfer',
                child: Text(
                  transfers.isEmpty
                      ? 'Transfer to agent queue'
                      : 'Resume chatbot',
                ),
              ),
              const PopupMenuItem(
                value: 'info',
                child: Text('Contact & notes'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete_conversation',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_sweep_outlined),
                  title: Text('Delete conversation permanently'),
                ),
              ),
              const PopupMenuItem(
                value: 'delete_contact',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.person_remove_outlined,
                    color: Colors.red,
                  ),
                  title: Text(
                    'Delete contact permanently',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Material(
              color: nexusPink,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: _call,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 15,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 29),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _callAllowed
                              ? 'Call Access Allowed'
                              : callPermission['status'] == 'pending'
                              ? 'Call Access Pending'
                              : 'Request Call Access',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        _callAllowed
                            ? Icons.open_in_new_rounded
                            : Icons.send_outlined,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    contactName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.contact['phone_number']?.toString() ?? '',
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      selectedAccount ?? 'WhatsApp',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (transfers.isNotEmpty)
            MaterialBanner(
              content: const Text(
                'Agent transfer is active for this conversation.',
              ),
              actions: [
                TextButton(
                  onPressed: _transferChatbot,
                  child: const Text('Resume chatbot'),
                ),
              ],
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadMessages,
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: messages.length,
                itemBuilder: (_, i) => _MessageTile(
                  message: messages[i],
                  repo: widget.repo,
                  onReply: () => setState(() => replyingTo = messages[i]),
                  onReact: (emoji) async {
                    await widget.repo.sendReaction(
                      contactId,
                      messages[i]['id'].toString(),
                      emoji,
                    );
                    await _loadMessages(silent: true);
                  },
                ),
              ),
            ),
          ),
          if (replyingTo != null)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _preview(replyingTo!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => replyingTo = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          _composer(),
        ],
      ),
    );
  }

  Future<void> _deleteConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete conversation?'),
        content: const Text(
          'All messages, notes and conversation state will be permanently removed. The contact and call history will remain. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repo.deleteConversation(contactId);
      if (mounted)
        setState(() {
          messages = [];
          transfers = [];
        });
      _snack('Conversation permanently deleted');
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  Future<void> _deleteContact() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete contact?'),
        content: Text(
          '$contactName and all related messages, notes, transfers, permissions and call history will be permanently removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repo.deleteContact(contactId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  Future<void> _showInfo() async {
    final notes = await widget.repo.notes(contactId);
    final note = TextEditingController();
    Map<String, dynamic> session = {};
    try {
      session = await widget.repo.sessionData(contactId);
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .82,
        maxChildSize: .96,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(18),
          children: [
            Text(contactName, style: Theme.of(context).textTheme.titleLarge),
            Text(widget.contact['phone_number']?.toString() ?? ''),
            const SizedBox(height: 12),
            Text('Assigned: ${widget.contact['assigned_user_id'] ?? '-'}'),
            Text(
              'Tags: ${widget.contact['tags'] is List ? (widget.contact['tags'] as List).join(', ') : '-'}',
            ),
            if (session.isNotEmpty) ...[
              const SizedBox(height: 16),
              ExpansionTile(
                title: const Text('Session data'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(session),
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 28),
            Text('Notes', style: Theme.of(context).textTheme.titleMedium),
            for (final item in notes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text((item['content'] ?? '').toString()),
                subtitle: Text(
                  (item['created_by_name'] ?? item['created_at'] ?? '')
                      .toString(),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Add note'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                if (note.text.trim().isEmpty) return;
                await widget.repo.addNote(contactId, note.text.trim());
                if (context.mounted) Navigator.pop(context);
                _showInfo();
              },
              child: const Text('Save note'),
            ),
          ],
        ),
      ),
    );
    note.dispose();
  }
}

class _FormattingToolbar extends StatefulWidget {
  const _FormattingToolbar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final VoidCallback onChanged;
  @override
  State<_FormattingToolbar> createState() => _FormattingToolbarState();
}

class _FormattingToolbarState extends State<_FormattingToolbar> {
  void wrap(String before, String after) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(0, text.length)
        : text.length;
    final selected = text.substring(start, end);
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(start, end, '$before$selected$after'),
      selection: TextSelection(
        baseOffset: start + before.length,
        extentOffset: start + before.length + selected.length,
      ),
    );
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Container(
    color: nexusCream,
    child: Row(
      children: [
        IconButton(
          onPressed: () => wrap('*', '*'),
          icon: const Icon(Icons.format_bold),
        ),
        IconButton(
          onPressed: () => wrap('_', '_'),
          icon: const Icon(Icons.format_italic),
        ),
        IconButton(
          onPressed: () => wrap('~', '~'),
          icon: const Icon(Icons.format_strikethrough),
        ),
        IconButton(
          onPressed: () => wrap('```', '```'),
          icon: const Icon(Icons.code),
        ),
      ],
    ),
  );
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.repo,
    required this.onReply,
    required this.onReact,
  });
  final Map<String, dynamic> message;
  final DataRepository repo;
  final VoidCallback onReply;
  final Future<void> Function(String emoji) onReact;

  @override
  Widget build(BuildContext context) {
    final outgoing = message['direction']?.toString() == 'outgoing';
    final type = message['message_type']?.toString() ?? 'text';
    final content = message['content'];
    final body = content is Map
        ? (content['body'] ?? '').toString()
        : content?.toString() ?? '';
    final media = message['media_url'] != null;
    final reactions = message['reactions'];

    final dot = Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.only(top: 7),
      decoration: BoxDecoration(
        color: outgoing ? nexusPink : nexusBlue,
        shape: BoxShape.circle,
      ),
    );
    final messageBody = Container(
      constraints: const BoxConstraints(maxWidth: 330),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: outgoing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (message['reply_to_message'] is Map)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: nexusCream,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _preview(
                  Map<String, dynamic>.from(message['reply_to_message'] as Map),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (media) _mediaCard(context, type),
          if (type == 'location') _locationCard(context, body),
          if (type == 'contacts') _contactCard(body),
          if (body.isNotEmpty && type != 'location' && type != 'contacts')
            Text(
              body,
              textAlign: outgoing ? TextAlign.right : TextAlign.left,
              style: const TextStyle(fontSize: 16, height: 1.35),
            ),
          if (body.isEmpty &&
              !media &&
              type != 'location' &&
              type != 'contacts')
            Text('[$type]'),
          if (message['interactive_data'] is Map) _interactive(context),
          if (reactions is List && reactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Wrap(
                spacing: 4,
                children: [
                  for (final r in reactions)
                    Chip(
                      label: Text((r is Map ? r['emoji'] : r).toString()),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _time(message['created_at']),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (outgoing) ...[
                const SizedBox(width: 4),
                Icon(
                  message['status'] == 'read' ? Icons.done_all : Icons.done,
                  size: 14,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _actions(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: outgoing ? [messageBody, dot] : [dot, messageBody],
          ),
        ),
      ),
    );
  }

  Widget _mediaCard(BuildContext context, String type) {
    final url = '${repo.api.apiBase}/media/${message['id']}';
    if (type == 'image' || type == 'sticker') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: GestureDetector(
          onTap: () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.network(
              url,
              headers: const {'Accept': 'image/*'},
              width: 260,
              height: 210,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _attachment(type, url),
            ),
          ),
        ),
      );
    }
    return _attachment(message['media_filename']?.toString() ?? type, url);
  }

  Widget _attachment(String label, String url) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.attach_file),
    title: Text(label),
    trailing: const Icon(Icons.open_in_new),
    onTap: () =>
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
  );

  Widget _locationCard(BuildContext context, String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is Map) {
        final lat = value['latitude'];
        final lng = value['longitude'];
        final title = value['name'] ?? value['address'] ?? 'Location';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.location_on_outlined),
          title: Text(title.toString()),
          subtitle: Text('$lat, $lng'),
          onTap: () => launchUrl(
            Uri.parse('https://www.google.com/maps?q=$lat,$lng'),
            mode: LaunchMode.externalApplication,
          ),
        );
      }
    } catch (_) {}
    return const Text('[Location]');
  }

  Widget _contactCard(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is List) {
        return Column(
          children: [
            for (final item in value.whereType<Map>())
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text((item['name'] ?? 'Contact').toString()),
                subtitle: Text((item['phones'] ?? '').toString()),
              ),
          ],
        );
      }
    } catch (_) {}
    return const Text('[Contact]');
  }

  Widget _interactive(BuildContext context) {
    final data = Map<String, dynamic>.from(message['interactive_data'] as Map);
    final buttons = data['buttons'] ?? data['rows'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data['button_text'] != null || data['display_text'] != null)
          OutlinedButton(
            onPressed: data['url'] != null
                ? () => launchUrl(
                    Uri.parse(data['url'].toString()),
                    mode: LaunchMode.externalApplication,
                  )
                : null,
            child: Text(
              (data['button_text'] ?? data['display_text']).toString(),
            ),
          ),
        if (buttons is List)
          for (final b in buttons.whereType<Map>())
            OutlinedButton(
              onPressed: b['url'] != null
                  ? () => launchUrl(
                      Uri.parse(b['url'].toString()),
                      mode: LaunchMode.externalApplication,
                    )
                  : null,
              child: Text(
                (b['title'] ?? b['text'] ?? b['reply']?['title'] ?? 'Action')
                    .toString(),
              ),
            ),
      ],
    );
  }

  Future<void> _actions(BuildContext context) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            for (final emoji in const ['👍', '❤️', '😂', '😮', '😢', '🙏'])
              ListTile(
                leading: Text(emoji, style: const TextStyle(fontSize: 22)),
                title: Text('React $emoji'),
                onTap: () => Navigator.pop(context, emoji),
              ),
          ],
        ),
      ),
    );
    if (value == 'reply') onReply();
    if (value != null && value != 'reply') await onReact(value);
  }
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.items,
    required this.titleOf,
    required this.subtitleOf,
  });
  final String title;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) titleOf;
  final String Function(Map<String, dynamic>) subtitleOf;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .75,
        maxChildSize: .95,
        builder: (_, controller) => ListView.separated(
          controller: controller,
          itemCount: items.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index == 0)
              return ListTile(
                title: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              );
            final item = items[index - 1];
            return ListTile(
              title: Text(titleOf(item)),
              subtitle: Text(
                subtitleOf(item),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.pop(context, item),
            );
          },
        ),
      ),
    );
  }
}

String _preview(Map<String, dynamic> message) {
  final content = message['content'];
  if (content is Map && content['body'] != null)
    return content['body'].toString();
  if (content is String && content.isNotEmpty) return content;
  return '[${message['message_type'] ?? 'message'}]';
}

String _time(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
