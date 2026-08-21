import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';
import 'realtime.dart';

class DataRepository extends ChangeNotifier {
  DataRepository(this.api, {this.realtime, String cacheNamespace = 'default'})
    : _cacheNamespace = cacheNamespace {
    _cacheReady = _restoreCache();
    unawaited(
      _cacheReady.then((_) {
        if (!_disposed)
          _realtimeSubscription = realtime?.events.listen(_applyRealtime);
      }),
    );
  }

  final WhatomateApi api;
  final RealtimeService? realtime;
  final String _cacheNamespace;
  late final Future<void> _cacheReady;
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  Timer? _persistTimer;
  bool _disposed = false;
  List<Map<String, dynamic>> _cachedContacts = [];
  final Map<String, List<Map<String, dynamic>>> _cachedMessages = {};

  Future<List<Map<String, dynamic>>> cachedContacts({String? search}) async {
    await _cacheReady;
    final query = search?.trim().toLowerCase() ?? '';
    final items = query.isEmpty
        ? _cachedContacts
        : _cachedContacts.where((contact) {
            final name = (contact['profile_name'] ?? contact['name'] ?? '')
                .toString()
                .toLowerCase();
            final phone = (contact['phone_number'] ?? '')
                .toString()
                .toLowerCase();
            return name.contains(query) || phone.contains(query);
          });
    return items.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<List<Map<String, dynamic>>> cachedMessages(String contactId) async {
    await _cacheReady;
    return (_cachedMessages[contactId] ?? const <Map<String, dynamic>>[])
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>?> cachedContact(String id) async {
    await _cacheReady;
    final index = _cachedContacts.indexWhere(
      (item) => item['id']?.toString() == id,
    );
    return index < 0 ? null : Map<String, dynamic>.from(_cachedContacts[index]);
  }

  List<Map<String, dynamic>> _items(dynamic data, List<String> keys) {
    dynamic current = data;
    if (current is Map && current.containsKey('data'))
      current = current['data'];
    if (current is List) {
      return current
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (current is Map) {
      for (final key in keys) {
        final value = current[key];
        if (value is List) {
          return value
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      final value = current['items'];
      if (value is List) {
        return value
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> contacts({
    String? search,
    int page = 1,
  }) async {
    await _cacheReady;
    final r = await api.get(
      '/contacts',
      query: {
        'page': page,
        'limit': 50,
        if (search != null && search.trim().isNotEmpty)
          'search': _normalizePhoneSearch(search),
      },
    );
    final loaded = _items(r.data, const ['contacts']);
    _mergeContacts(
      loaded,
      replace: page == 1 && (search == null || search.trim().isEmpty),
    );
    return loaded;
  }

  Future<Map<String, dynamic>?> contact(String id) async {
    await _cacheReady;
    final data = api.unwrap(await api.get('/contacts/$id'));
    if (data is! Map) return null;
    final contact = Map<String, dynamic>.from(data);
    _mergeContacts([contact], replace: false);
    return contact;
  }

  Future<Map<String, dynamic>> createContact(
    String phone, {
    String? name,
  }) async {
    final data = api.unwrap(
      await api.post(
        '/contacts',
        data: {
          'phone_number': _normalizePhoneSearch(phone),
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        },
      ),
    );
    if (data is! Map) throw ApiException('Invalid contact response');
    final contact = Map<String, dynamic>.from(data);
    _mergeContacts([contact], replace: false);
    return contact;
  }

  Future<void> updateContact(String id, Map<String, dynamic> patch) async {
    await api.put('/contacts/$id', data: patch);
  }

  Future<void> deleteContact(String id) async {
    await api.delete('/contacts/$id');
    _cachedContacts.removeWhere((item) => item['id']?.toString() == id);
    _cachedMessages.remove(id);
    _changed();
  }

  Future<void> deleteConversation(String id) async {
    await api.delete('/contacts/$id/conversation');
    _cachedMessages.remove(id);
    final index = _cachedContacts.indexWhere(
      (item) => item['id']?.toString() == id,
    );
    if (index >= 0) {
      _cachedContacts[index] = {
        ..._cachedContacts[index],
        'unread_count': 0,
        'last_message': null,
      };
    }
    _changed();
  }

  Future<void> assignContact(String id, String? userId) async {
    await api.put('/contacts/$id/assign', data: {'user_id': userId});
  }

  Future<void> updateContactTags(String id, List<String> tags) async {
    await api.put('/contacts/$id/tags', data: {'tags': tags});
  }

  Future<Map<String, dynamic>> sessionData(String id) async {
    final data = api.unwrap(await api.get('/contacts/$id/session-data'));
    return data is Map ? Map<String, dynamic>.from(data) : {};
  }

  Future<List<Map<String, dynamic>>> messages(
    String contactId, {
    String? account,
  }) async {
    await _cacheReady;
    final r = await api.get(
      '/contacts/$contactId/messages',
      query: {
        'limit': 80,
        if (account != null && account.isNotEmpty) 'account': account,
      },
    );
    final loaded = _items(r.data, const ['messages']);
    _cachedMessages[contactId] = loaded;
    _changed();
    return loaded;
  }

  Future<Map<String, dynamic>> sendMessage(
    String contactId, {
    required String type,
    required dynamic content,
    String? account,
    String? replyTo,
    Map<String, dynamic>? interactive,
  }) async {
    final data = api.unwrap(
      await api.post(
        '/contacts/$contactId/messages',
        data: {
          'type': type,
          'content': content,
          if (replyTo != null) 'reply_to_message_id': replyTo,
          if (account != null && account.isNotEmpty)
            'whatsapp_account': account,
          if (interactive != null) 'interactive': interactive,
        },
      ),
    );
    if (data is! Map) throw ApiException('Invalid message response');
    final message = Map<String, dynamic>.from(data);
    _upsertMessage(contactId, message);
    return message;
  }

  Future<Map<String, dynamic>> sendText(
    String contactId,
    String body, {
    String? account,
    String? replyTo,
  }) => sendMessage(
    contactId,
    type: 'text',
    content: {'body': body},
    account: account,
    replyTo: replyTo,
  );

  Future<Map<String, dynamic>> sendMedia(
    String contactId,
    File file, {
    String? mimeType,
    String? caption,
    String? account,
  }) async {
    final mime = mimeType ?? _guessMime(file.path);
    final type = mime.startsWith('image/')
        ? 'image'
        : mime.startsWith('video/')
        ? 'video'
        : mime.startsWith('audio/')
        ? 'audio'
        : 'document';
    final size = await file.length();
    final max = type == 'image'
        ? 5 * 1024 * 1024
        : (14.5 * 1024 * 1024).round();
    if (size > max) {
      throw ApiException(
        type == 'image'
            ? 'Images must be 5 MB or smaller'
            : 'Media must be smaller than 14.5 MB',
      );
    }
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.uri.pathSegments.isEmpty
            ? 'attachment'
            : file.uri.pathSegments.last,
      ),
      'contact_id': contactId,
      'type': type,
      if (caption != null && caption.trim().isNotEmpty)
        'caption': caption.trim(),
      if (account != null && account.isNotEmpty) 'whatsapp_account': account,
    });
    final response = await api.dio.post<dynamic>(
      '/messages/media',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    final data = api.unwrap(response);
    if (data is! Map) throw ApiException('Invalid media response');
    final message = Map<String, dynamic>.from(data);
    _upsertMessage(contactId, message);
    return message;
  }

  Future<void> sendReaction(
    String contactId,
    String messageId,
    String emoji,
  ) async {
    await api.post(
      '/contacts/$contactId/messages/$messageId/reaction',
      data: {'emoji': emoji},
    );
  }

  Future<void> sendTemplate(
    String contactId,
    String templateName, {
    Map<String, String>? templateParams,
    Map<String, String>? headerParams,
    Map<String, String>? buttonParams,
    String? account,
  }) async {
    await api.post(
      '/messages/template',
      data: {
        'contact_id': contactId,
        'template_name': templateName,
        if (templateParams != null) 'template_params': templateParams,
        if (headerParams != null) 'header_params': headerParams,
        if (buttonParams != null) 'button_params': buttonParams,
        if (account != null && account.isNotEmpty) 'account_name': account,
      },
    );
  }

  Future<List<Map<String, dynamic>>> templates({
    String? account,
    String? search,
  }) async {
    final r = await api.get(
      '/templates',
      query: {
        'page': 1,
        'limit': 100,
        if (account != null && account.isNotEmpty) 'account': account,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    return _items(r.data, const ['templates']);
  }

  Future<List<Map<String, dynamic>>> cannedResponses({String? search}) async {
    final r = await api.get(
      '/canned-responses',
      query: {
        'page': 1,
        'limit': 100,
        'active_only': 'true',
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    return _items(r.data, const ['canned_responses']);
  }

  Future<void> recordCannedUse(String id) async {
    await api.post('/canned-responses/$id/use', data: {});
  }

  Future<void> createAgentTransfer(
    String contactId,
    String account, {
    String? agentId,
    String? notes,
  }) async {
    await api.post(
      '/chatbot/transfers',
      data: {
        'contact_id': contactId,
        'whatsapp_account': account,
        if (agentId != null) 'agent_id': agentId,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'source': 'manual',
      },
    );
  }

  Future<void> resumeAgentTransfer(String id) async {
    await api.put('/chatbot/transfers/$id/resume', data: {});
  }

  Future<List<Map<String, dynamic>>> activeAgentTransfers({
    String? contactId,
  }) async {
    final r = await api.get(
      '/chatbot/transfers',
      query: {'status': 'active', 'limit': 100, 'offset': 0, 'include': 'all'},
    );
    final items = _items(r.data, const ['transfers']);
    if (contactId == null) return items;
    return items
        .where((t) => t['contact_id']?.toString() == contactId)
        .toList();
  }

  Future<void> markRead(String contactId) async {
    final index = _cachedContacts.indexWhere(
      (item) => item['id']?.toString() == contactId,
    );
    if (index >= 0) {
      _cachedContacts[index] = {..._cachedContacts[index], 'unread_count': 0};
      _changed();
    }
    await api.post('/contacts/$contactId/mark-read', data: {});
  }

  Future<List<Map<String, dynamic>>> notes(String contactId) async {
    final r = await api.get('/contacts/$contactId/notes', query: {'limit': 50});
    return _items(r.data, const ['notes']);
  }

  Future<void> addNote(String contactId, String content) async {
    await api.post('/contacts/$contactId/notes', data: {'content': content});
  }

  Future<List<Map<String, dynamic>>> accounts() async {
    return _items((await api.get('/accounts')).data, const ['accounts']);
  }

  Future<List<Map<String, dynamic>>> callLogs({String? search}) async {
    final r = await api.get(
      '/call-logs',
      query: {
        'page': 1,
        'limit': 50,
        if (search != null && search.isNotEmpty) 'phone': search,
      },
    );
    return _items(r.data, const ['call_logs']);
  }

  Future<int> clearCallHistory() async {
    final data = api.unwrap(await api.delete('/call-logs/history'));
    if (data is Map)
      return int.tryParse(data['deleted']?.toString() ?? '') ?? 0;
    return 0;
  }

  Future<List<Map<String, dynamic>>> waitingCallTransfers() async {
    final r = await api.get('/call-transfers', query: {'status': 'waiting'});
    return _items(r.data, const ['call_transfers']);
  }

  Future<List<Map<String, dynamic>>> teams() async {
    return _items((await api.get('/teams')).data, const ['teams']);
  }

  Future<List<Map<String, dynamic>>> users() async {
    return _items((await api.get('/users')).data, const ['users']);
  }

  Future<List<Map<String, dynamic>>> tags() async {
    return _items((await api.get('/tags', query: {'limit': 100})).data, const [
      'tags',
    ]);
  }

  Future<List<Map<String, dynamic>>> genericList(
    String path,
    List<String> keys, {
    Map<String, dynamic>? query,
  }) async {
    final r = await api.get(path, query: query ?? {'page': 1, 'limit': 50});
    return _items(r.data, keys);
  }

  Future<Map<String, dynamic>> dashboard() async {
    final data = api.unwrap(await api.get('/analytics/dashboard'));
    return data is Map ? Map<String, dynamic>.from(data) : {};
  }

  String _normalizePhoneSearch(String input) {
    final value = input.trim().replaceFirst(RegExp(r'^\+'), '');
    if (RegExp(r'^[\d\s+()\-]+$').hasMatch(value)) {
      return value.replaceAll(RegExp(r'[\s+()\-]'), '');
    }
    return value;
  }

  String _guessMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx'))
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    return 'application/octet-stream';
  }

  void _applyRealtime(RealtimeEvent event) {
    if (event.type == 'new_message') {
      final raw = event.payload['message'];
      final message = raw is Map
          ? Map<String, dynamic>.from(raw)
          : Map<String, dynamic>.from(event.payload);
      final contactId = message['contact_id']?.toString();
      if (contactId == null || contactId.isEmpty) return;
      _upsertMessage(contactId, message, notify: false);
      final index = _cachedContacts.indexWhere(
        (item) => item['id']?.toString() == contactId,
      );
      final incoming = message['direction']?.toString() == 'incoming';
      if (index >= 0) {
        final current = _cachedContacts.removeAt(index);
        _cachedContacts.insert(0, {
          ...current,
          if (message['profile_name'] != null)
            'profile_name': message['profile_name'],
          'last_message': message,
          if (incoming) 'unread_count': _asInt(current['unread_count']) + 1,
        });
      } else {
        _cachedContacts.insert(0, {
          'id': contactId,
          'profile_name': message['profile_name'],
          'last_message': message,
          'unread_count': incoming ? 1 : 0,
        });
      }
      _changed();
      return;
    }

    if (event.type == 'status_update' || event.type == 'reaction_update') {
      final messageId =
          event.payload['message_id']?.toString() ??
          event.payload['id']?.toString();
      if (messageId == null) return;
      for (final entry in _cachedMessages.entries) {
        final index = entry.value.indexWhere(
          (message) => message['id']?.toString() == messageId,
        );
        if (index >= 0) {
          entry.value[index] = {...entry.value[index], ...event.payload};
          _changed();
          return;
        }
      }
    }

    if (event.type == 'contact_update') {
      final id =
          event.payload['id']?.toString() ??
          event.payload['contact_id']?.toString();
      if (id == null) return;
      final index = _cachedContacts.indexWhere(
        (item) => item['id']?.toString() == id,
      );
      if (index >= 0) {
        _cachedContacts[index] = {..._cachedContacts[index], ...event.payload};
      } else {
        _cachedContacts.insert(0, Map<String, dynamic>.from(event.payload));
      }
      _changed();
    }
  }

  void _mergeContacts(
    List<Map<String, dynamic>> loaded, {
    required bool replace,
  }) {
    if (replace) {
      _cachedContacts = loaded;
    } else {
      final merged = {
        for (final item in _cachedContacts) item['id']?.toString(): item,
      };
      for (final item in loaded) {
        merged[item['id']?.toString()] = item;
      }
      _cachedContacts = merged.values.toList();
    }
    _changed();
  }

  void _upsertMessage(
    String contactId,
    Map<String, dynamic> message, {
    bool notify = true,
  }) {
    final items = _cachedMessages.putIfAbsent(contactId, () => []);
    final id = message['id']?.toString();
    final index = id == null
        ? -1
        : items.indexWhere((item) => item['id']?.toString() == id);
    if (index >= 0) {
      items[index] = {...items[index], ...message};
    } else {
      items.add(message);
    }
    items.sort(
      (a, b) => (a['created_at'] ?? '').toString().compareTo(
        (b['created_at'] ?? '').toString(),
      ),
    );
    if (items.length > 120) items.removeRange(0, items.length - 120);
    if (notify) _changed();
  }

  int _asInt(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

  void _changed() {
    if (_disposed) return;
    notifyListeners();
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), _persistCache);
  }

  Future<File> _cacheFile() async {
    final directory = await getApplicationSupportDirectory();
    var hash = 2166136261;
    for (final byte in utf8.encode('${api.serverRoot}|$_cacheNamespace')) {
      hash = ((hash ^ byte) * 16777619) & 0xffffffff;
    }
    return File(
      '${directory.path}${Platform.pathSeparator}data_cache_$hash.json',
    );
  }

  Future<void> _restoreCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final contacts = decoded['contacts'];
      if (contacts is List) {
        _cachedContacts = contacts
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      final messages = decoded['messages'];
      if (messages is Map) {
        for (final entry in messages.entries) {
          if (entry.value is List) {
            _cachedMessages[entry.key.toString()] = (entry.value as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
          }
        }
      }
    } catch (_) {
      // A corrupt or obsolete cache is non-fatal; the network refresh below
      // rebuilds it with the current API representation.
    }
  }

  Future<void> _persistCache() async {
    try {
      await _cacheReady;
      final file = await _cacheFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'contacts': _cachedContacts, 'messages': _cachedMessages}),
        flush: true,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _persistTimer?.cancel();
    unawaited(_persistCache());
    _realtimeSubscription?.cancel();
    super.dispose();
  }
}
