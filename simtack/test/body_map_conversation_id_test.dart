import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/features/body_map/ui/body_map_screen.dart';

/// The conversation id decides which stored turns a patient's question is
/// answered with. It used to be a timestamp — `conv_<millis>_<micros % 10000>`
/// — which is only a few thousand candidates per shift, so on a shared hospital
/// address one patient could reach another's conversation by guessing.
BodyMapScreen _screen() => BodyMapScreen(
      patientId: 1,
      gender: 'Male',
      weightKg: 70,
      heightCm: 175,
    );

void main() {
  test('conversation ids are unique per screen', () {
    final ids = List.generate(64, (_) => _screen().conversationId);

    expect(ids.toSet(), hasLength(ids.length));
  });

  test('conversation ids do not carry the current timestamp', () {
    // The first eight digits of millisecondsSinceEpoch are stable for over a
    // day, so the old format always contained this prefix. A random 32-character
    // hex id matches a given eight-digit run with probability ~1e-8.
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    final stampPrefix = now.substring(0, 8);

    final ids = List.generate(64, (_) => _screen().conversationId);

    expect(ids.where((id) => id.contains(stampPrefix)), isEmpty);
  });

  test('conversation ids are long enough to be unguessable', () {
    final id = _screen().conversationId;

    expect(id, startsWith('conv_'));
    // 'conv_' plus 32 hex characters: 128 bits of randomness.
    expect(id.length, greaterThanOrEqualTo(36));
  });
}
