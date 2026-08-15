import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:test/test.dart';

void main() {
  test('nearest fresh anchor wins and missing anchor degrades', () {
    final resolver = ZoneResolver({
      'a': const ZoneAnchor(anchorId: 'a', logicalZone: 'Gate A'),
      'b': const ZoneAnchor(anchorId: 'b', logicalZone: 'Gate B'),
    });
    expect(
      resolver.estimate([
        const BeaconObservation(anchorId: 'a', rssi: -80, observedAtMs: 100),
        const BeaconObservation(anchorId: 'b', rssi: -50, observedAtMs: 100),
      ], 100).logicalZone,
      'Gate B',
    );
    expect(resolver.estimate(const [], 100).uncertainty, 'unknown');
  });
}
