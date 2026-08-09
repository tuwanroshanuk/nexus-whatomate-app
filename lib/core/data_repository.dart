import 'dart:io';

import 'package:dio/dio.dart';

import 'api_client.dart';

class DataRepository {
  DataRepository(this.api);
  final WhatomateApi api;

  List<Map<String, dynamic>> _items(dynamic data, List<String> keys) {
    dynamic current = data;
    if (current is Map && current.containsKey('data')) current = current['data'];
    if (current is List) {
      return current.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (current is Map) {
      for (final key in keys) {
        final value = current[key];
        if (value is List) {
          return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
      final value = current['items'];
      if (value is List) {
        return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> contacts({String? search, int page = 1}) async {
    final r = await api.get('/contacts', query: {
      'page': page,
      'limit': 50,
      if (search != null && search.trim().isNotEmpty) 'search': _normalizePhoneSearch(search),
    });
    return _items(r.data, const ['contacts']);
  }

  Future<Map<String, dynamic>?> contact(String id) async {
    final data = api.unwrap(await api.get('/contacts/$id'));
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  Future<Map<String, dynamic>> createContact(String phone, {String? name}) async {
    final data = api.unwrap(await api.post('/contacts', data: {
      'phone_number': _normalizePhoneSearch(phone),
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
    }));
    if (data is! Map) throw ApiException('Invalid contact response');
    return Map<String, dynamic>.from(data);
  }

  Future<void> updateContact(String id, Map<String, dynamic> patch) async {
    await api.put('/contacts/$id', data: patch);
  }

  Future<void> deleteContact(String id) async {
    await api.delete('/contacts/$id');
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

  Future<List<Map<String, dynamic>>> messages(String contactId, {String? account}) async {
    final r = await api.get('/contacts/$contactId/messages', query: {
      'limit': 80,
      if (account != null && account.isNotEmpty) 'account': account,
    });
    return _items(r.data, const ['messages']);
  }

  Future<Map<String, dynamic>> sendMessage(
    String contactId, {
    required String type,
    required dynamic content,
    String? account,
    String? replyTo,
    Map<String, dynamic>? interactive,
  }) async {
    final data = api.unwrap(await api.post('/contacts/$contactId/messages', data: {
      'type': type,
      'content': content,
      if (replyTo != null) 'reply_to_message_id': replyTo,
      if (account != null && account.isNotEmpty) 'whatsapp_account': account,
      if (interactive != null) 'interactive': interactive,
    }));
    if (data is! Map) throw ApiException('Invalid message response');
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> sendText(String contactId, String body,
      {String? account, String? replyTo}) =>
      sendMessage(contactId,
          type: 'text', content: {'body': body}, account: account, replyTo: replyTo);

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
    final max = type == 'image' ? 5 * 1024 * 1024 : (14.5 * 1024 * 1024).round();
    if (size > max) {
      throw ApiException(type == 'image'
          ? 'Images must be 5 MB or smaller'
          : 'Media must be smaller than 14.5 MB');
    }
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path,
          filename: file.uri.pathSegments.isEmpty ? 'attachment' : file.uri.pathSegments.last),
      'contact_id': contactId,
      'type': type,
      if (caption != null && caption.trim().isNotEmpty) 'caption': caption.trim(),
      if (account != null && account.isNotEmpty) 'whatsapp_account': account,
    });
    final response = await api.dio.post<dynamic>('/messages/media', data: form,
        options: Options(contentType: 'multipart/form-data'));
    final data = api.unwrap(response);
    if (data is! Map) throw ApiException('Invalid media response');
    return Map<String, dynamic>.from(data);
  }

  Future<void> sendReaction(String contactId, String messageId, String emoji) async {
    await api.post('/contacts/$contactId/messages/$messageId/reaction', data: {'emoji': emoji});
  }

  Future<void> sendTemplate(
    String contactId,
    String templateName, {
    Map<String, String>? templateParams,
    Map<String, String>? headerParams,
    Map<String, String>? buttonParams,
    String? account,
  }) async {
    await api.post('/messages/template', data: {
      'contact_id': contactId,
      'template_name': templateName,
      if (templateParams != null) 'template_params': templateParams,
      if (headerParams != null) 'header_params': headerParams,
      if (buttonParams != null) 'button_params': buttonParams,
      if (account != null && account.isNotEmpty) 'account_name': account,
    });
  }

  Future<List<Map<String, dynamic>>> templates({String? account, String? search}) async {
    final r = await api.get('/templates', query: {
      'page': 1,
      'limit': 100,
      if (account != null && account.isNotEmpty) 'account': account,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    return _items(r.data, const ['templates']);
  }

  Future<List<Map<String, dynamic>>> cannedResponses({String? search}) async {
    final r = await api.get('/canned-responses', query: {
      'page': 1,
      'limit': 100,
      'active_only': 'true',
      if (search != null && search.isNotEmpty) 'search': search,
    });
    return _items(r.data, const ['canned_responses']);
  }

  Future<void> recordCannedUse(String id) async {
    await api.post('/canned-responses/$id/use', data: {});
  }

  Future<void> createAgentTransfer(String contactId, String account,
      {String? agentId, String? notes}) async {
    await api.post('/chatbot/transfers', data: {
      'contact_id': contactId,
      'whatsapp_account': account,
      if (agentId != null) 'agent_id': agentId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'source': 'manual',
    });
  }

  Future<void> resumeAgentTransfer(String id) async {
    await api.put('/chatbot/transfers/$id/resume', data: {});
  }

  Future<List<Map<String, dynamic>>> activeAgentTransfers({String? contactId}) async {
    final r = await api.get('/chatbot/transfers', query: {
      'status': 'active',
      'limit': 100,
      'offset': 0,
      'include': 'all',
    });
    final items = _items(r.data, const ['transfers']);
    if (contactId == null) return items;
    return items.where((t) => t['contact_id']?.toString() == contactId).toList();
  }

  Future<void> markRead(String contactId) async {
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
    final r = await api.get('/call-logs', query: {
      'page': 1,
      'limit': 50,
      if (search != null && search.isNotEmpty) 'phone': search,
    });
    return _items(r.data, const ['call_logs']);
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
    return _items((await api.get('/tags', query: {'limit': 100})).data, const ['tags']);
  }

  Future<List<Map<String, dynamic>>> genericList(String path, List<String> keys,
      {Map<String, dynamic>? query}) async {
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
    if (lower.endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    return 'application/octet-stream';
  }
}
