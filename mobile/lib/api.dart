import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Thrown on HTTP 401: the session is missing or expired, so the app shows the login screen.
class AuthException extends ApiException {
  AuthException(super.message);
}

/// Thin client for the CVSAFE FastAPI backend (used by the mobile app and the web panel).
class ApiClient {
  ApiClient(String baseUrl, {this.token})
      : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  final String baseUrl;
  String? token;
  final http.Client _http = http.Client();
  static const _short = Duration(seconds: 10);

  String url(String path) => path.startsWith('http') ? path : '$baseUrl$path';
  String get _tokenQuery => token == null ? '' : '&token=${Uri.encodeQueryComponent(token!)}';
  String snapshotUrl(String cameraId) =>
      '$baseUrl/cameras/$cameraId/snapshot?t=${DateTime.now().millisecondsSinceEpoch}$_tokenQuery';
  String frameUrl(String cameraId, {int bust = 0}) => '$baseUrl/cameras/$cameraId/frame?b=$bust$_tokenQuery';
  String reportUrl(String range) => '$baseUrl/reports/summary.pdf?range=$range$_tokenQuery';

  Map<String, String> get _auth => token == null ? {} : {'Authorization': 'Bearer $token'};

  Future<dynamic> _get(String path, {Duration timeout = _short}) async {
    final r = await _http.get(Uri.parse(url(path)), headers: _auth).timeout(timeout);
    return _decode(r);
  }

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse(url(path)))
      ..headers.addAll({..._auth, 'Content-Type': 'application/json'})
      ..body = jsonEncode(body ?? {});
    final r = await http.Response.fromStream(await _http.send(req).timeout(_short));
    return _decode(r);
  }

  Future<dynamic> _post(String path, [Object? body]) => _send('POST', path, body);

  dynamic _decode(http.Response r) {
    final text = utf8.decode(r.bodyBytes);
    if (r.statusCode >= 400) {
      String msg = 'Server error ${r.statusCode}';
      try {
        final d = jsonDecode(text);
        if (d is Map && d['detail'] != null) {
          final det = d['detail'];
          msg = det is List && det.isNotEmpty && det.first is Map ? (det.first['msg'] ?? det.toString()).toString() : det.toString();
        }
      } catch (_) {}
      if (r.statusCode == 401) throw AuthException(msg);
      throw ApiException(msg);
    }
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  Map<String, dynamic> _map(dynamic v) => (v as Map).cast<String, dynamic>();

  // ---------------------------------------------------------------- auth
  /// Returns the user and stores the session token on this client.
  Future<UserInfo> login(String username, String password) async {
    final d = _map(await _post('/auth/login', {'username': username, 'password': password}));
    token = d['token'] as String;
    return UserInfo.fromJson(_map(d['user']));
  }

  Future<UserInfo> me() async => UserInfo.fromJson(_map(await _get('/auth/me')));

  Future<void> logout() async {
    try {
      await _post('/auth/logout');
    } catch (_) {}
    token = null;
  }

  Future<void> changeOwnPassword(String password) => _post('/auth/password', {'password': password});

  Future<List<UserInfo>> users() async =>
      (await _get('/users') as List).map((e) => UserInfo.fromJson(_map(e))).toList();

  Future<UserInfo> createUser(String username, String name, String role, String password) async =>
      UserInfo.fromJson(_map(await _post('/users', {'username': username, 'name': name, 'role': role, 'password': password})));

  Future<void> deleteUser(int id) => _send('DELETE', '/users/$id');

  Future<void> resetPassword(int id, String password) => _post('/users/$id/password', {'password': password});

  // ------------------------------------------------------------ status/site
  Future<Health> health() async => Health.fromJson(_map(await _get('/health')));

  Future<SiteInfo> site() async => SiteInfo.fromJson(_map(await _get('/site')));

  Future<void> saveCamera({required String id, required String name, String? source, String? subcontractor}) =>
      _post('/cameras', {'id': id, 'name': name, 'source': source, 'subcontractor': subcontractor});

  Future<void> deleteCamera(String id) => _send('DELETE', '/cameras/$id');

  Future<List<Zone>> saveZones(String cameraId, List<Zone> zones) async =>
      (await _send('PUT', '/cameras/$cameraId/zones', zones.map((z) => z.toJson()).toList()) as List)
          .map((e) => Zone.fromJson(_map(e)))
          .toList();

  Future<void> uploadReference(String cameraId, Uint8List bytes, String filename) async {
    final req = http.MultipartRequest('POST', Uri.parse(url('/cameras/$cameraId/reference')))
      ..headers.addAll(_auth)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    _decode(await http.Response.fromStream(await _http.send(req).timeout(const Duration(minutes: 1))));
  }

  Future<void> saveSubcontractor({String? id, required String name, String trade = '', int workers = 0}) =>
      _post('/subcontractors', {'id': id, 'name': name, 'trade': trade, 'workers': workers});

  Future<void> deleteSubcontractor(String id) => _send('DELETE', '/subcontractors/$id');

  // ------------------------------------------------------------- incidents
  Future<List<Incident>> incidents({String? status, String? category, String? cameraId, int limit = 60, int offset = 0}) async {
    final q = StringBuffer('/incidents?limit=$limit&offset=$offset');
    if (status != null) q.write('&status=$status');
    if (category != null) q.write('&category=$category');
    if (cameraId != null) q.write('&camera_id=${Uri.encodeQueryComponent(cameraId)}');
    final list = await _get(q.toString()) as List;
    return list.map((e) => Incident.fromJson(_map(e))).toList();
  }

  Future<Incident> incident(int id) async => Incident.fromJson(_map(await _get('/incidents/$id')));

  Future<Incident> acknowledge(int id, {String? note}) async =>
      Incident.fromJson(_map(await _post('/incidents/$id/ack', {'note': note})));

  Future<Incident> falseAlarm(int id, {String? note}) async =>
      Incident.fromJson(_map(await _post('/incidents/$id/false_alarm', {'note': note})));

  Future<Incident> action(int id, String kind) async =>
      Incident.fromJson(_map(await _post('/incidents/$id/action', {'kind': kind})));

  Future<Analytics> analytics(String range) async => Analytics.fromJson(_map(await _get('/analytics?range=$range')));

  // -------------------------------------------------------------- analysis
  Future<ImageScanResult> analyzeImage(Uint8List bytes, String filename,
      {String? cameraId, bool createIncidents = true}) async {
    final req = http.MultipartRequest('POST', Uri.parse(url('/analyze/image')))
      ..headers.addAll(_auth)
      ..fields['create_incidents'] = createIncidents.toString()
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    if (cameraId != null) req.fields['camera_id'] = cameraId;
    final streamed = await _http.send(req).timeout(const Duration(minutes: 2));
    final r = await http.Response.fromStream(streamed);
    return ImageScanResult.fromJson(_map(_decode(r)));
  }

  /// Uploads a video and returns the background job; poll [job] for progress.
  Future<VideoJob> analyzeVideo({String? path, Uint8List? bytes, required String filename,
      String? cameraId, bool createIncidents = true}) async {
    final req = http.MultipartRequest('POST', Uri.parse(url('/analyze/video')))
      ..headers.addAll(_auth)
      ..fields['create_incidents'] = createIncidents.toString();
    if (cameraId != null) req.fields['camera_id'] = cameraId;
    if (!kIsWeb && path != null) {
      req.files.add(await http.MultipartFile.fromPath('file', path, filename: filename));
    } else if (bytes != null) {
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    } else {
      throw ApiException('No video data');
    }
    final streamed = await _http.send(req).timeout(const Duration(minutes: 10));
    final r = await http.Response.fromStream(streamed);
    return VideoJob.fromJson(_map(_decode(r)));
  }

  Future<VideoJob> job(String id) async => VideoJob.fromJson(_map(await _get('/jobs/$id')));
}
