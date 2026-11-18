import 'dart:async';
import 'dart:convert';

import 'package:cvsafe_core/cvsafe_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default false-alarm reasons matching `backend/app/rules.py` (used until the server list is loaded).
const List<FalseAlarmReason> kDefaultFalseAlarmReasons = [
  FalseAlarmReason('wrong_detection', 'Wrong detection'),
  FalseAlarmReason('authorised_person', 'Authorised person in the zone'),
  FalseAlarmReason('reflection_shadow', 'Reflection or shadow'),
  FalseAlarmReason('other', 'Other'),
];

/// Factory for creating an [ApiClient]; overridden in tests to inject a `MockClient`.
typedef ApiClientFactory = ApiClient Function(String baseUrl, {String? token, void Function()? onUnauthorized});

final apiClientFactoryProvider = Provider<ApiClientFactory>(
  (ref) => (baseUrl, {token, onUnauthorized}) => ApiClient(baseUrl, token: token, onUnauthorized: onUnauthorized),
);

/// Controls whether the 5-second background polling timer starts automatically.
/// Disabled in widget tests so `WidgetTester` does not report pending timers.
final pollEnabledProvider = Provider<bool>((ref) => true);

/// Immutable snapshot of the web panel's application state.
class PanelState {
  const PanelState({
    required this.serverUrl,
    required this.api,
    this.user,
    this.needsLogin = false,
    this.loading = true,
    this.online = false,
    this.everOnline = false,
    this.lastSync,
    this.lastError,
    this.health,
    this.site,
    this.incidents = const [],
    this.analytics = const {},
    this.analyticsRange = 'today',
    this.analyticsLoading = false,
    this.analyticsError,
    this.falseAlarmReasons = kDefaultFalseAlarmReasons,
  });

  final String serverUrl;
  final ApiClient api;
  final UserInfo? user;
  final bool needsLogin;
  final bool loading;
  final bool online;
  final bool everOnline;
  final double? lastSync;
  final String? lastError;

  final Health? health;
  final SiteInfo? site;
  final List<Incident> incidents;
  final Map<String, Analytics> analytics;
  final String analyticsRange;
  final bool analyticsLoading;
  final String? analyticsError;
  final List<FalseAlarmReason> falseAlarmReasons;

  bool get isAuthenticated => user != null && !needsLogin && everOnline;
  List<Incident> get openIncidents => incidents.where((i) => i.isOpen).toList();
  int get criticalOpen => openIncidents.where((i) => i.isCritical).length;

  String falseAlarmReasonLabel(String? code) {
    if (code == null || code.isEmpty) return 'Other';
    for (final r in falseAlarmReasons) {
      if (r.code == code) return r.label;
    }
    return code;
  }

  static const _unset = Object();

  PanelState copyWith({
    String? serverUrl,
    ApiClient? api,
    Object? user = _unset,
    bool? needsLogin,
    bool? loading,
    bool? online,
    bool? everOnline,
    Object? lastSync = _unset,
    Object? lastError = _unset,
    Object? health = _unset,
    Object? site = _unset,
    List<Incident>? incidents,
    Map<String, Analytics>? analytics,
    String? analyticsRange,
    bool? analyticsLoading,
    Object? analyticsError = _unset,
    List<FalseAlarmReason>? falseAlarmReasons,
  }) {
    return PanelState(
      serverUrl: serverUrl ?? this.serverUrl,
      api: api ?? this.api,
      user: identical(user, _unset) ? this.user : user as UserInfo?,
      needsLogin: needsLogin ?? this.needsLogin,
      loading: loading ?? this.loading,
      online: online ?? this.online,
      everOnline: everOnline ?? this.everOnline,
      lastSync: identical(lastSync, _unset) ? this.lastSync : lastSync as double?,
      lastError: identical(lastError, _unset) ? this.lastError : lastError as String?,
      health: identical(health, _unset) ? this.health : health as Health?,
      site: identical(site, _unset) ? this.site : site as SiteInfo?,
      incidents: incidents ?? this.incidents,
      analytics: analytics ?? this.analytics,
      analyticsRange: analyticsRange ?? this.analyticsRange,
      analyticsLoading: analyticsLoading ?? this.analyticsLoading,
      analyticsError: identical(analyticsError, _unset) ? this.analyticsError : analyticsError as String?,
      falseAlarmReasons: falseAlarmReasons ?? this.falseAlarmReasons,
    );
  }
}

/// Riverpod controller managing server connection, authentication, site configuration,
/// incidents polling and analytics for the CVSAFE Web Panel.
class PanelController extends Notifier<PanelState> {
  static const _prefKey = 'server_url';
  static const _tokenKey = 'session_token';
  static const _userKey = 'session_user';
  static const defaultUrl = 'http://localhost:8000';

  final Set<int> _seen = {};
  bool _firstLoad = true;
  bool _baselined = false;
  Timer? _timer;
  final StreamController<Incident> _newAlerts = StreamController<Incident>.broadcast();

  /// Fires whenever a new open incident arrives after the initial baseline load.
  Stream<Incident> get newAlerts => _newAlerts.stream;

  ApiClient _buildClient(String url, {String? token}) {
    final factory = ref.read(apiClientFactoryProvider);
    return factory(url, token: token, onUnauthorized: _handleUnauthorized);
  }

  void _handleUnauthorized() {
    _clearSession();
    _resetTracking();
    state = state.copyWith(
      user: null,
      needsLogin: true,
      online: true,
      incidents: const [],
      site: null,
      analytics: const {},
    );
  }

  @override
  PanelState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _newAlerts.close();
    });
    final initialClient = _buildClient(defaultUrl);
    Future.microtask(init);
    return PanelState(serverUrl: defaultUrl, api: initialClient);
  }

  Future<void> init() async {
    var serverUrl = defaultUrl;
    String? token;
    UserInfo? savedUser;
    try {
      final prefs = await SharedPreferences.getInstance();
      serverUrl = prefs.getString(_prefKey) ?? defaultUrl;
      token = prefs.getString(_tokenKey);
      final u = prefs.getString(_userKey);
      if (u != null) {
        savedUser = UserInfo.fromJson((jsonDecode(u) as Map).cast<String, dynamic>());
      }
    } catch (_) {}

    state = state.copyWith(
      serverUrl: serverUrl,
      api: _buildClient(serverUrl, token: token),
      user: savedUser,
    );
    await refresh();
    _timer?.cancel();
    if (ref.read(pollEnabledProvider)) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => refresh(quiet: true));
    }
  }

  void _resetTracking() {
    _seen.clear();
    _firstLoad = true;
    _baselined = false;
  }

  Future<void> _clearSession([SharedPreferences? prefs]) async {
    state.api.token = null;
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      await p.remove(_tokenKey);
      await p.remove(_userKey);
    } catch (_) {}
  }

  Future<void> setServer(String url) async {
    final trimmed = url.trim();
    final changed = trimmed != state.serverUrl;
    final token = changed ? null : state.api.token;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, trimmed);
      if (changed) await _clearSession(prefs);
    } catch (_) {}
    _resetTracking();
    state = state.copyWith(
      serverUrl: trimmed,
      api: _buildClient(trimmed, token: token),
      user: changed ? null : state.user,
      everOnline: false,
      incidents: const [],
      site: null,
      analytics: const {},
    );
    await refresh();
  }

  /// Signs in to [url] with [username] and [password]. Throws [ApiException] on failure.
  Future<void> login(String url, String username, String password) async {
    final trimmedUrl = url.trim();
    final client = _buildClient(trimmedUrl);
    final u = await client.login(username.trim(), password);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, trimmedUrl);
      await prefs.setString(_tokenKey, client.token!);
      await prefs.setString(_userKey, jsonEncode(u.toJson()));
    } catch (_) {}
    _resetTracking();
    state = state.copyWith(
      serverUrl: trimmedUrl,
      api: client,
      user: u,
      needsLogin: false,
      everOnline: false,
      incidents: const [],
      site: null,
      analytics: const {},
    );
    await refresh();
  }

  Future<void> logout() async {
    await state.api.logout();
    await _clearSession();
    _resetTracking();
    state = state.copyWith(
      user: null,
      needsLogin: true,
      everOnline: false,
      incidents: const [],
      site: null,
      analytics: const {},
    );
  }

  Future<void> reloadSite() async {
    try {
      final site = await state.api.site();
      state = state.copyWith(site: site);
    } catch (_) {}
  }

  Future<void> refresh({bool quiet = false}) async {
    if (!quiet) {
      state = state.copyWith(loading: true);
    }
    try {
      final health = await state.api.health();
      if (state.api.token == null) {
        _firstLoad = false;
        state = state.copyWith(
          health: health,
          online: true,
          needsLogin: true,
          loading: false,
        );
        return;
      }
      final user = state.user ?? await state.api.me();
      final list = await state.api.incidents();
      var site = state.site;
      if (site == null || !state.online || !quiet) {
        site = await state.api.site();
      }
      var reasons = state.falseAlarmReasons;
      if (!state.everOnline) {
        try {
          final loaded = await state.api.falseAlarmReasons();
          if (loaded.isNotEmpty) reasons = loaded;
        } catch (_) {}
      }
      final merged = _mergeIncidents(list);
      _firstLoad = false;
      state = state.copyWith(
        health: health,
        user: user,
        site: site,
        incidents: merged,
        falseAlarmReasons: reasons,
        online: true,
        everOnline: true,
        lastSync: DateTime.now().millisecondsSinceEpoch / 1000,
        lastError: null,
        needsLogin: false,
        loading: false,
        analytics: state.everOnline ? state.analytics : const {},
        analyticsError: state.everOnline ? state.analyticsError : null,
      );
    } on AuthException {
      await _clearSession();
      _resetTracking();
      _firstLoad = false;
      state = state.copyWith(
        user: null,
        online: true,
        needsLogin: true,
        loading: false,
        incidents: const [],
        site: null,
        analytics: const {},
      );
    } catch (e) {
      final err = (state.online || _firstLoad || !quiet) ? e.toString() : state.lastError;
      _firstLoad = false;
      state = state.copyWith(
        online: false,
        loading: false,
        lastError: err,
      );
    }
  }

  List<Incident> _mergeIncidents(List<Incident> list) {
    final old = {for (final i in state.incidents) i.id: i};
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
    return list;
  }

  void replaceIncident(Incident inc) {
    final copy = [...state.incidents];
    final idx = copy.indexWhere((i) => i.id == inc.id);
    if (idx >= 0) {
      copy[idx] = inc;
    } else {
      copy.insert(0, inc);
    }
    _seen.add(inc.id);
    state = state.copyWith(incidents: copy);
  }

  Future<Incident?> loadIncidentDetail(int id) async {
    try {
      final full = await state.api.incident(id);
      replaceIncident(full);
      return full;
    } catch (_) {
      return null;
    }
  }

  Future<void> loadAnalytics(String range) async {
    state = state.copyWith(
      analyticsRange: range,
      analyticsLoading: true,
      analyticsError: null,
    );
    try {
      final a = await state.api.analytics(range);
      state = state.copyWith(
        analytics: {...state.analytics, range: a},
        analyticsLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        analyticsLoading: false,
        analyticsError: e.toString(),
      );
    }
  }
}

final panelControllerProvider = NotifierProvider<PanelController, PanelState>(PanelController.new);
