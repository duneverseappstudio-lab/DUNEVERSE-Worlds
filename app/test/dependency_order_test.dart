import 'dart:math';

import 'package:imperator_forge/dependency_order.dart' as candidate;
import 'package:flutter_test/flutter_test.dart';

void check(bool ok, String label) {
  if (!ok) throw StateError(label);
}

List<String>? oracle(Set<String> bodies, Map<String, String?> hosts) {
  final left = Set<String>.of(bodies), result = <String>[];
  while (left.isNotEmpty) {
    final ready =
        left
            .where((id) => hosts[id] == null || result.contains(hosts[id]))
            .toList()
          ..sort();
    if (ready.isEmpty) return null;
    result.add(ready.first);
    left.remove(ready.first);
  }
  return result;
}

void main() {
  test(
    'dependency order matches independent randomized oracle and wide heap',
    () {
      final random = Random(742);
      var cases = 0;
      for (var n = 0; n <= 10; n++) {
        for (var run = 0; run < 500; run++) {
          final ids = List.generate(n, (i) => 'id$i')..shuffle(random);
          final bodies = ids.toSet();
          final hosts = <String, String?>{};
          for (final id in ids) {
            if (random.nextBool()) {
              hosts[id] = random.nextInt(n + 1) == n
                  ? null
                  : ids[random.nextInt(n)];
            }
          }
          final expected = oracle(bodies, hosts);
          try {
            final actual = candidate.dependencyOrder(bodies, hosts);
            check(expected != null, 'cycle accepted');
            check(actual.join(',') == expected!.join(','), 'wrong ready order');
            final reverse = candidate.dependencyOrder(
              ids.reversed.toSet(),
              Map.fromEntries(hosts.entries.toList().reversed),
            );
            check(actual.join(',') == reverse.join(','), 'nondeterministic');
          } on ArgumentError {
            check(expected == null, 'valid graph rejected');
          }
          cases++;
        }
      }
      for (final graph in [
        <String, String?>{'ghost': null},
        <String, String?>{'a': 'ghost'},
        <String, String?>{'a': ''},
      ]) {
        var rejected = false;
        try {
          candidate.dependencyOrder({'a'}, graph);
        } on ArgumentError {
          rejected = true;
        }
        check(rejected, 'bad reference accepted');
      }
      final fan = List.generate(
        10000,
        (i) => 'b${i.toString().padLeft(5, '0')}',
      );
      final order = candidate.dependencyOrder(fan.reversed.toSet(), {
        for (final id in fan.skip(1)) id: fan.first,
      });
      check(order.length == 10000, 'wide heap');
      check(order.join(',') == fan.join(','), 'heap order');
      expect(cases, 5500);
    },
  );
}
