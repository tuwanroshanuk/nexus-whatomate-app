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

  Future<List<Map<String, dynamic>>> messages(String contactId, {String? account}) async {
    final r = await api.get('/contacts/$contactId/messages', query: {
      'limit': 80,
      if (account != null && account.isNotEmpty) 'account': account,
    });
    return _items(r.data, const ['messages']);
  }

  Future<Map<String, dynamic>> sendText(String contactId, String body,
      {String? account, String? replyTo}) async {
    final data = api.unwrap(await api.post('/contacts/$contactId/messages', data: {
      'type': 'text',
      'content': {'body': body},
      if (replyTo != null) 'reply_to_message_id': replyTo,
      if (account != null && account.isNotEmpty) 'whatsapp_account': account,
    }));
    if (data is! Map) throw ApiException('Invalid message response');
    return Map<String, dynamic>.from(data);
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
}
