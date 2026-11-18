import 'dart:convert';

import 'package:cvsafe_core/cvsafe_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> requests;

  ApiClient client(http.Response Function(http.Request r) handler, {void Function()? onUnauthorized}) {
    requests = [];
    return ApiClient('http://server:8000/',
        token: 'tok',
        onUnauthorized: onUnauthorized,
        httpClient: MockClient((r) async {
          requests.add(r);
          return handler(r);
        }));
  }

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  test('trims the trailing slash and sends the bearer token', () async {
    final api = client((_) => json({'id': 1, 'username': 'admin', 'name': 'A', 'role': 'admin'}));
    expect(api.baseUrl, 'http://server:8000');
    await api.me();
    expect(requests.single.url.toString(), 'http://server:8000/auth/me');
    expect(requests.single.headers['Authorization'], 'Bearer tok');
  });

  test('falseAlarm sends the reason code and note', () async {
    final api = client((_) => json({'id': 7, 'created_at': 1.0, 'status': 'false_alarm', 'false_alarm_reason': 'other'}));
    final inc = await api.falseAlarm(7, reason: 'authorised_person', note: 'crane operator');
    expect(requests.single.url.path, '/incidents/7/false_alarm');
    expect(jsonDecode(requests.single.body), {'reason': 'authorised_person', 'note': 'crane operator'});
    expect(inc.status, 'false_alarm');
  });

  test('updateUser sends only the changed fields with PATCH', () async {
    final api = client((_) => json({'id': 4, 'username': 'u', 'name': 'U', 'role': 'ohs', 'is_active': false}));
    final u = await api.updateUser(4, isActive: false);
    expect(requests.single.method, 'PATCH');
    expect(jsonDecode(requests.single.body), {'is_active': false});
    expect(u.isActive, isFalse);
  });

  test('falseAlarmReasons parses the lookup list', () async {
    final api = client((_) => json([
          {'code': 'wrong_detection', 'label': 'Wrong detection'},
          {'code': 'other', 'label': 'Other'},
        ]));
    final reasons = await api.falseAlarmReasons();
    expect(reasons.map((r) => r.code), ['wrong_detection', 'other']);
  });

  test('maps FastAPI errors to ApiException with status code', () async {
    final api = client((_) => json({'detail': 'At least one active admin must remain'}, 400));
    await expectLater(
      api.updateUser(1, role: 'field'),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', 'At least one active admin must remain')
          .having((e) => e.statusCode, 'statusCode', 400)),
    );
  });

  test('401 calls onUnauthorized and throws AuthException', () async {
    var called = 0;
    final api = client((_) => json({'detail': 'Login required'}, 401), onUnauthorized: () => called++);
    await expectLater(api.site(), throwsA(isA<AuthException>()));
    expect(called, 1);
  });
}
