import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'demo.dart';
import 'models.dart';

/// App-wide state: server connection, incidents (polled), site and analytics.
class AppState extends ChangeNotifier {
  static const _prefKey = 'server_url';
  static const _tokenKey = 'session_token';
  static const _userKey = 'session_user';

  /// Browser -> same computer; Android emulator -> host machine.
  static String get defaultUrl => kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000';

  String serverUrl = defaultUrl;
  ApiClient api = ApiClient(defaultUrl);

  /// Logged-in user; null until login. [needsLogin] is true when the server is
  /// reachable but there is no valid session.
  UserInfo? user;
  bool needsLogin = false;

  bool loading = true;
  bool online = false; // true when the backend answers right now
  bool everOnline = false; // connected at least once since the server was set
  double? lastSync;
  String? lastError;

  Health? health;
  SiteInfo? site;
  List<Incident> incidents = [];
  final Map<String, Analytics> analytics = {};
  String analyticsRange = 'today';
  bool analyticsLoading = false;
  String? analyticsError; // stops automatic retries until the user retries

  int tab = 0;
  int? selectedIncidentId;
  String? selectedCameraId;

  final Set<int> _seen = {};
  bool _firstLoad = true;
  bool _baselined = false; // first real incident list received; later new ones raise a banner
  Timer? _timer;

  /// Fires when a new open incident arrives (used for the in-app alert banner).
  final StreamController<Incident> _newAlerts = StreamController<Incident>.broadcast();
  Stream<Incident> get newAlerts => _newAlerts.stream;

  /// Demo data is only used when the server was never reached.
  bool get demo => !everOnline;
  List<Incident> get openIncidents => incidents.where((i) => i.isOpen).toList();
  int get criticalOpen => openIncidents.where((i) => i.isCritical).length;

  Incident? get selectedIncident {
    if (incidents.isEmpty) return null;
    if (selectedIncidentId != null) {
      for (final i in incidents) {
        if (i.id == selectedIncidentId) return i;
      }
    }
    final open = openIncidents;
    return open.isNotEmpty ? open.first : incidents.first;
  }

  Future<void> init() async {
    String? token;
    try {
      final prefs = await SharedPreferences.getInstance();
      serverUrl = prefs.getString(_prefKey) ?? defaultUrl;
      token = prefs.getString(_tokenKey);
      final u = prefs.getString(_userKey);
      if (u != null) user = UserInfo.fromJson((jsonDecode(u) as Map).cast<String, dynamic>());
    } catch (_) {}
    api = ApiClient(serverUrl, token: token);
    await refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => refresh(quiet: true));
  }

  Future<void> setServer(String url) async {
    final changed = url.trim() != serverUrl;
    serverUrl = url.trim();
    // a session belongs to one server; keep it only if the address did not change
    api = ApiClient(serverUrl, token: changed ? null : api.token);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, serverUrl);
      if (changed) await _clearSession(prefs);
    } catch (_) {}
    _resetData();
    await refresh();
  }

  void _resetData() {
    _seen.clear();
    _firstLoad = true;
    _baselined = false;
    everOnline = false;
    incidents = [];
    site = null;
    analytics.clear();
    selectedIncidentId = null;
  }

  Future<void> _clearSession([SharedPreferences? prefs]) async {
    user = null;
    api.token = null;
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      await p.remove(_tokenKey);
      await p.remove(_userKey);
    } catch (_) {}
  }

  /// Logs in; throws [ApiException] with a readable message on failure.
  Future<void> login(String url, String username, String password) async {
    final client = ApiClient(url.trim());
    final u = await client.login(username.trim(), password);
    serverUrl = url.trim();
    api = client;
    user = u;
    needsLogin = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, serverUrl);
      await prefs.setString(_tokenKey, client.token!);
      await prefs.setString(_userKey, jsonEncode(u.toJson()));
    } catch (_) {}
    _resetData();
    await refresh();
  }

  Future<void> logout() async {
    await api.logout();
    await _clearSession();
    _resetData();
    needsLogin = true;
    tab = 0;
    notifyListeners();
  }

  Future<void> reloadSite() async {
    try {
      site = await api.site();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refresh({bool quiet = false}) async {
    if (!quiet) {
      loading = true;
      notifyListeners();
    }
    try {
      health = await api.health(); // public endpoint: tells us the server is reachable
      if (api.token == null) {
        online = true;
        needsLogin = true;
        loading = false;
        _firstLoad = false;
        notifyListeners();
        return;
      }
      user ??= await api.me();
      final list = await api.incidents();
      if (!everOnline) {
        analytics.clear(); // drop demo numbers once the real server answers
        analyticsError = null;
      }
      if (site == null || !online || !quiet) {
        site = await api.site();
      }
      online = true;
      everOnline = true;
      lastSync = DateTime.now().millisecondsSinceEpoch / 1000;
      lastError = null;
      needsLogin = false;
      _mergeIncidents(list);
    } on AuthException {
      // session expired or revoked
      await _clearSession();
      _resetData();
      online = true;
      needsLogin = true;
    } catch (e) {
      if (online || _firstLoad || !quiet) {
        lastError = e.toString();
      }
      if (!everOnline) {
        // never connected: stay usable with demo data
        site = DemoData.site();
        if (incidents.isEmpty || incidents.first.source != 'demo') incidents = DemoData.incidents();
      }
      // after a connection drop the last synced alerts stay on screen
      online = false;
    }
    _firstLoad = false;
    loading = false;
    notifyListeners();
  }

  void _mergeIncidents(List<Incident> list) {
    // keep timelines we already loaded for the detail view
    final old = {for (final i in incidents) i.id: i};
    for (final i in list) {
      final prev = old[i.id];
      if (prev != null && i.timeline.isEmpty) i.timeline = prev.timeline;
    }
    if (_baselined) {
      for (final i in list) {
        if (i.isOpen && !_seen.contains(i.id)) _newAlerts.add(i);
      }
    }
    _seen.addAll(list.map((i) => i.id));
    _baselined = true;
    incidents = list;
  }

  Future<void> loadIncidentDetail(int id) async {
    if (!online) return;
    try {
      _replace(await api.incident(id));
    } catch (_) {}
  }

  void _replace(Incident inc) {
    final idx = incidents.indexWhere((i) => i.id == inc.id);
    if (idx >= 0) {
      incidents[idx] = inc;
    } else {
      incidents.insert(0, inc);
    }
    _seen.add(inc.id);
    notifyListeners();
  }

  Future<void> loadAnalytics(String range) async {
    analyticsRange = range;
    analyticsLoading = true;
    analyticsError = null;
    if (demo) {
      analyticsLoading = false;
      analytics[range] = DemoData.analytics();
      notifyListeners();
      return;
    }
    try {
      analytics[range] = await api.analytics(range);
    } catch (e) {
      analyticsError = e.toString();
    }
    analyticsLoading = false;
    notifyListeners();
  }

  // ------------------------------------------------------------ actions
  Future<String?> acknowledge(Incident inc) => _act(inc, 'acknowledged', () => api.acknowledge(inc.id));

  Future<String?> falseAlarm(Incident inc, {String? note}) =>
      _act(inc, 'false_alarm', () => api.falseAlarm(inc.id, note: note));

  Future<String?> fieldAction(Incident inc, String kind) => _act(inc, null, () => api.action(inc.id, kind), kind: kind);

  /// Returns an error message, or null on success.
  Future<String?> _act(Incident inc, String? newStatus, Future<Incident> Function() call, {String? kind}) async {
    if (!demo && !online) return 'No connection to the server. Try again.';
    if (demo) {
      // demo mode: update locally
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      if (newStatus != null) {
        inc.status = newStatus;
        inc.ackAt = now;
      }
      inc.timeline = [...inc.timeline, TimelineEvent(now, 'user', newStatus ?? kind ?? 'action')];
      notifyListeners();
      return null;
    }
    try {
      _replace(await call());
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void openEvidence(int incidentId) {
    selectedIncidentId = incidentId;
    tab = 1;
    notifyListeners();
    loadIncidentDetail(incidentId);
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  void addIncidentsFromScan(List<int> ids) {
    for (final id in ids) {
      loadIncidentDetail(id);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _newAlerts.close();
    super.dispose();
  }
}
