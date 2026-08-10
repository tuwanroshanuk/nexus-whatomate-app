import 'package:flutter_test/flutter_test.dart';
import 'package:whatomate_app/core/calling.dart';

void main() {
  test('call state is active only for non-terminal call statuses', () {
    expect(const CallState(status: 'ringing').active, isTrue);
    expect(const CallState(status: 'answered').active, isTrue);
    expect(const CallState(status: 'idle').active, isFalse);
    expect(const CallState(status: 'ended').active, isFalse);
    expect(const CallState(status: 'failed').active, isFalse);
  });
}
