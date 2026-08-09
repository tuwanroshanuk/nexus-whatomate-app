import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

class SessionController extends ChangeNotifier {
  SessionController(this.api);
  final WhatomateApi api;

  Map<String, dynamic>? user;
  bool booting = true;
  bool busy = false;
  String? error;

  bool get authenticated => user != null;
  String? get organizationId => user?['organization_id']?.toString();
  String? get userId => user?['id']?.toString();
  String get displayName => (user?['full_name'] ?? user?['email'] ?? 'Agent').toString();

  Future<void> bootstrap() async {
    booting = true;
    error = null;
    notifyListeners();
    try {
      final server = await api.savedServer;
      if (server != null && server.isNotEmpty) {
        await refreshUser();
      }
    } catch (_) {
      user = null;
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<void> configureServer(String server) async {
    await api.setServer(server);
    user = null;
    error = null;
    notifyListeners();
  }

  Future<void> login(String server, String email, String password) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await api.setServer(server);
      final response = await api.post('/auth/login', data: {
        'email': email.trim(),
        'password': password,
      });
      final data = api.unwrap(response);
      final rawUser = data is Map ? data['user'] : null;
      if (rawUser is! Map) throw ApiException('Login response did not include a user');
      user = Map<String, dynamic>.from(rawUser);
      final org = organizationId;
      if (org != null) await api.setOrganization(org);
    } catch (e) {
      error = api.normalize(e).message;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> refreshUser() async {
    try {
      final response = await api.get('/me');
      final data = api.unwrap(response);
      if (data is Map) {
        user = Map<String, dynamic>.from(data);
        final org = organizationId;
        if (org != null) await api.setOrganization(org);
        notifyListeners();
        return true;
      }
    } catch (e) {
      final normalized = api.normalize(e);
      if (normalized.statusCode == 401) user = null;
    }
    notifyListeners();
    return false;
  }

  Future<void> switchOrganization(String organizationId) async {
    busy = true;
    notifyListeners();
    try {
      final response = await api.post('/auth/switch-org', data: {'organization_id': organizationId});
      final data = api.unwrap(response);
      final rawUser = data is Map ? data['user'] : null;
      if (rawUser is Map) user = Map<String, dynamic>.from(rawUser);
      await api.setOrganization(organizationId);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  bool hasPermission(String resource, [String action = 'read']) {
    if (user?['is_super_admin'] == true) return true;
    final role = user?['role'];
    final permissions = role is Map ? role['permissions'] : null;
    if (permissions is! List) return false;
    return permissions.any((entry) => entry is Map &&
        entry['resource']?.toString() == resource &&
        entry['action']?.toString() == action);
  }

  Future<void> setAvailability(bool available) async {
    final response = await api.put('/me/availability', data: {'is_available': available});
    final data = api.unwrap(response);
    if (data is Map && data['user'] is Map) {
      user = Map<String, dynamic>.from(data['user'] as Map);
    } else if (user != null) {
      user = {...user!, 'is_available': available};
    }
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> organizations() async {
    final response = await api.get('/me/organizations');
    final data = api.unwrap(response);
    final list = data is Map ? (data['organizations'] ?? data['items']) : data;
    if (list is! List) return [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<String?> websocketToken() async {
    final response = await api.get('/auth/ws-token');
    final data = api.unwrap(response);
    if (data is Map) return data['token']?.toString();
    return null;
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout', data: {});
    } catch (_) {}
    user = null;
    await api.clearSession();
    notifyListeners();
  }

  String debugUser() => jsonEncode(user);
}
