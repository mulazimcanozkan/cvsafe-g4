import 'package:cvsafe_mobile/demo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo data is consistent', () {
    expect(DemoData.incidents(), isNotEmpty);
    expect(DemoData.site().cameras.length, 4);
    expect(DemoData.analytics().leaderboard, isNotEmpty);
  });
}
