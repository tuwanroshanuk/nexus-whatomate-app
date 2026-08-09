import 'dart:async';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.data});
  final String message;
  final int? statusCode;
  final dynamic data;
  @override
  String toString() => message;
}

class WhatomateApi {
  WhatomateApi._(this.dio, this.cookies, this.storage);

  final Dio dio;
  final PersistCookieJar cookies;
  final FlutterSecureStorage storage;
  static const _serverKey = 'whatomate_server_url';
  static const _orgKey = 'whatomate_organization_id';
  bool _refreshing = false;
  Completer<bool>? _refreshCompleter;

  static Future<WhatomateApi> create() async {
    const storage = FlutterSecureStorage();
    final dir = await getApplicationSupportDirectory();
    final cookieDir = Directory('${dir.path}${Platform.pathSeparator}cookies');
    if (!cookieDir.existsSync()) cookieDir.createSync(recursive: true);
    final jar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage(cookieDir.path),
    );
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      validateStatus: (code) => code != null && code >= 200 && code < 300,
      responseType: ResponseType.json,
      headers: {'Accept': 'application/json'},
    ));
    final api = WhatomateApi._(dio, jar, storage);
    dio.interceptors.add(CookieManager(jar, ignoreInvalidCookies: true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: api._onRequest,
      onError: api._onError,
    ));
    await api._applyStoredServer();
    return api;
  }

  String get apiBase => dio.options.baseUrl;
  String get serverRoot {
    final base = dio.options.baseUrl;
    return base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
  }

  Future<String?> get savedServer => storage.read(key: _serverKey);
  Future<String?> get selectedOrganization => storage.read(key: _orgKey);

  Future<void> setServer(String input) async {
    var url = input.trim();
    if (url.isEmpty) throw ApiException('Server URL is required');
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/api')) url = url.substring(0, url.length - 4);
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) throw ApiException('Invalid server URL');
    dio.options.baseUrl = '$url/api';
    await storage.write(key: _serverKey, value: url);
  }

  Future<void> setOrganization(String? id) async {
    if (id == null || id.isEmpty) {
      await storage.delete(key: _orgKey);
    } else {
      await storage.write(key: _orgKey, value: id);
    }
  }

  Future<void> _applyStoredServer() async {
    final value = await storage.read(key: _serverKey);
    if (value != null && value.isNotEmpty) dio.options.baseUrl = '$value/api';
  }

  Future<void> _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (dio.options.baseUrl.isEmpty && !options.path.startsWith('http')) {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
        error: ApiException('Configure a Whatomate server first'),
      ));
      return;
    }
    final org = await selectedOrganization;
    if (org != null && org.isNotEmpty) options.headers['X-Organization-ID'] = org;

    final method = options.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD' && method != 'OPTIONS') {
      final uri = options.uri;
      final list = await cookies.loadForRequest(uri);
      for (final cookie in list) {
        if (cookie.name == 'whm_csrf') {
          options.headers['X-CSRF-Token'] = cookie.value;
          break;
        }
      }
    }
    handler.next(options);
  }

  Future<void> _onError(DioException error, ErrorInterceptorHandler handler) async {
    final request = error.requestOptions;
    if (error.response?.statusCode == 401 &&
        request.extra['whatomateRetried'] != true &&
        !request.path.contains('/auth/login') &&
        !request.path.contains('/auth/refresh')) {
      final refreshed = await refreshSession();
      if (refreshed) {
        try {
          request.extra['whatomateRetried'] = true;
          final response = await dio.fetch<dynamic>(request);
          handler.resolve(response);
          return;
        } catch (_) {}
      }
    }
    handler.next(error);
  }

  Future<bool> refreshSession() async {
    if (_refreshing) return (await _refreshCompleter!.future);
    _refreshing = true;
    _refreshCompleter = Completer<bool>();
    try {
      final response = await dio.post<dynamic>('/auth/refresh',
          options: Options(extra: {'whatomateRetried': true}));
      final ok = response.statusCode == 200;
      _refreshCompleter!.complete(ok);
      return ok;
    } catch (_) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      dio.get<dynamic>(path, queryParameters: query);
  Future<Response<dynamic>> post(String path, {dynamic data, Map<String, dynamic>? query}) =>
      dio.post<dynamic>(path, data: data, queryParameters: query);
  Future<Response<dynamic>> put(String path, {dynamic data, Map<String, dynamic>? query}) =>
      dio.put<dynamic>(path, data: data, queryParameters: query);
  Future<Response<dynamic>> patch(String path, {dynamic data, Map<String, dynamic>? query}) =>
      dio.patch<dynamic>(path, data: data, queryParameters: query);
  Future<Response<dynamic>> delete(String path, {dynamic data, Map<String, dynamic>? query}) =>
      dio.delete<dynamic>(path, data: data, queryParameters: query);

  dynamic unwrap(Response<dynamic> response) {
    final body = response.data;
    if (body is Map<String, dynamic> && body.containsKey('data')) return body['data'];
    return body;
  }

  ApiException normalize(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final data = error.response?.data;
      String? message;
      if (data is Map) {
        final direct = data['message'];
        final nested = data['error'];
        if (direct is String) message = direct;
        if (message == null && nested is Map && nested['message'] is String) {
          message = nested['message'] as String;
        }
      }
      return ApiException(
        message ?? error.message ?? 'Request failed',
        statusCode: error.response?.statusCode,
        data: data,
      );
    }
    return ApiException(error.toString());
  }

  Future<void> clearSession() async {
    await cookies.deleteAll();
    await storage.delete(key: _orgKey);
  }
}
