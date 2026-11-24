// Adapted from a Gemini-generated candidate after independent validation.
// Original and generated tests retained under verification/external_candidates.
import 'dart:collection';

/// Topologically orders motion dependencies so every host appears before its
/// dependents, including stationary bodies not present in [hostByMovingBody].
///
/// Ties among currently available bodies are broken lexicographically using
/// [String.compareTo].
///
/// Throws [ArgumentError] if any ID is empty, any moving body is not in
/// [bodyIds], any non-null host is not in [bodyIds], any body hosts itself,
/// or any dependency cycle exists.
List<String> dependencyOrder(
  Set<String> bodyIds,
  Map<String, String?> hostByMovingBody,
) {
  final Set<String> bodies = Set<String>.from(bodyIds);
  final Map<String, String?> movingHosts = Map<String, String?>.from(
    hostByMovingBody,
  );

  for (final String id in bodies) {
    if (id.isEmpty) {
      throw ArgumentError('Body IDs must not be empty.');
    }
  }

  final Map<String, int> inDegree = <String, int>{
    for (final String id in bodies) id: 0,
  };
  final Map<String, List<String>> dependentsByHost = <String, List<String>>{};

  movingHosts.forEach((String movingBody, String? host) {
    if (movingBody.isEmpty) {
      throw ArgumentError('Moving body ID must not be empty.');
    }
    if (!bodies.contains(movingBody)) {
      throw ArgumentError('Moving body "$movingBody" is not in bodyIds.');
    }
    if (host == null) {
      return;
    }
    if (host.isEmpty) {
      throw ArgumentError('Host ID for "$movingBody" must not be empty.');
    }
    if (!bodies.contains(host)) {
      throw ArgumentError(
        'Host "$host" for moving body "$movingBody" is not in bodyIds.',
      );
    }
    if (host == movingBody) {
      throw ArgumentError('Body "$movingBody" cannot be its own host.');
    }

    dependentsByHost.putIfAbsent(host, () => <String>[]).add(movingBody);
    inDegree[movingBody] = inDegree[movingBody]! + 1;
  });

  final _MinStringHeap ready = _MinStringHeap();
  inDegree.forEach((String id, int degree) {
    if (degree == 0) {
      ready.add(id);
    }
  });

  final List<String> ordered = <String>[];
  while (ready.isNotEmpty) {
    final String current = ready.removeFirst();
    ordered.add(current);

    final List<String>? children = dependentsByHost[current];
    if (children == null) {
      continue;
    }
    for (final String child in children) {
      final int updated = inDegree[child]! - 1;
      inDegree[child] = updated;
      if (updated == 0) {
        ready.add(child);
      }
    }
  }

  if (ordered.length != bodies.length) {
    throw ArgumentError('Cycle detected in motion dependencies.');
  }

  return UnmodifiableListView<String>(ordered);
}

final class _MinStringHeap {
  final List<String> _heap = <String>[];

  bool get isNotEmpty => _heap.isNotEmpty;

  void add(String value) {
    _heap.add(value);
    _siftUp(_heap.length - 1);
  }

  String removeFirst() {
    if (_heap.isEmpty) {
      throw StateError('Cannot remove from an empty heap.');
    }
    final String root = _heap.first;
    final String last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      _siftDown(0);
    }
    return root;
  }

  void _siftUp(int index) {
    int current = index;
    while (current > 0) {
      final int parent = (current - 1) >> 1;
      if (_heap[current].compareTo(_heap[parent]) < 0) {
        final String tmp = _heap[current];
        _heap[current] = _heap[parent];
        _heap[parent] = tmp;
        current = parent;
      } else {
        break;
      }
    }
  }

  void _siftDown(int index) {
    int current = index;
    final int length = _heap.length;
    while (true) {
      final int left = (current << 1) + 1;
      final int right = left + 1;
      int smallest = current;

      if (left < length && _heap[left].compareTo(_heap[smallest]) < 0) {
        smallest = left;
      }
      if (right < length && _heap[right].compareTo(_heap[smallest]) < 0) {
        smallest = right;
      }
      if (smallest != current) {
        final String tmp = _heap[current];
        _heap[current] = _heap[smallest];
        _heap[smallest] = tmp;
        current = smallest;
      } else {
        break;
      }
    }
  }
}
