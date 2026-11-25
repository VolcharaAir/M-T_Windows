import 'dart:collection';
import 'dart:convert';

import '../domain/turing.dart';

/// Reachability + conservative deterministic-transducer bisimulation.
/// A block may merge only when every read has the same write, direction and
/// successor block, including the absence of a transition. Head actions are
/// preserved exactly. Halt causes remain distinct.
class MachineOptimizer {
  TuringMachine optimize(TuringMachine machine) {
    final outgoing = <int, List<Transition>>{};
    for (final t in machine.transitions.values) {
      outgoing.putIfAbsent(t.from, () => []).add(t);
    }
    for (final list in outgoing.values) {
      list.sort((a, b) => a.read.compareTo(b.read));
    }
    List<int> reachable(int start, Map<int, List<Transition>> edges) {
      final seen = <int>{start},
          queue = Queue<int>()..add(start),
          order = <int>[];
      while (queue.isNotEmpty) {
        final q = queue.removeFirst();
        order.add(q);
        for (final t in edges[q] ?? <Transition>[]) {
          if (seen.add(t.to)) queue.add(t.to);
        }
      }
      return order;
    }

    final live = reachable(machine.initial, outgoing);
    String haltKey(int q) => machine.halts.contains(q)
        ? 'halt:${machine.states[q].description}:${machine.states[q].rule}'
        : 'work';
    var ids = <String, int>{};
    var blocks = {
      for (final q in live) q: ids.putIfAbsent(haltKey(q), () => ids.length),
    };
    var stable = false;
    // A budget prevents pathological refinement chains from stalling the UI.
    // If convergence is not reached, use singleton blocks: never merge an
    // unproved equivalence merely because a refinement budget was reached.
    for (var pass = 0; pass < 64; pass++) {
      ids = {};
      final next = <int, int>{};
      for (final q in live) {
        final signature = jsonEncode([
          haltKey(q),
          for (final t in outgoing[q] ?? <Transition>[])
            [t.read, t.write, t.move.index, blocks[t.to]],
        ]);
        next[q] = ids.putIfAbsent(signature, () => ids.length);
      }
      if (live.every((q) => blocks[q] == next[q])) {
        blocks = next;
        stable = true;
        break;
      }
      blocks = next;
    }
    if (!stable) {
      blocks = {for (var i = 0; i < live.length; i++) live[i]: i};
    }
    final members = <int, List<int>>{};
    for (final q in live) {
      members.putIfAbsent(blocks[q]!, () => []).add(q);
    }
    final edges = <int, List<Transition>>{};
    for (final entry in members.entries) {
      edges[entry.key] = [
        for (final t in outgoing[entry.value.first] ?? <Transition>[])
          Transition(entry.key, t.read, blocks[t.to]!, t.write, t.move),
      ];
    }
    final ordered = reachable(blocks[machine.initial]!, edges);
    final haltBlocks = {
      for (final q in live.where(machine.halts.contains)) blocks[q]!,
    };
    // Working states first, in BFS order; then explicit STOP states. IDs are
    // zero-based internally; the machine's canonical labels are S_1, S_2, ….
    final order = [
      ...ordered.where((q) => !haltBlocks.contains(q)),
      ...ordered.where(haltBlocks.contains),
    ];
    final remap = {for (var i = 0; i < order.length; i++) order[i]: i};
    final states = <StateInfo>[];
    for (final block in order) {
      final originals = members[block]!,
          first = machine.states[originals.first];
      final descriptions = {
        for (final q in originals) machine.states[q].description,
      };
      final rules = {for (final q in originals) machine.states[q].rule};
      states.add(
        StateInfo(
          remap[block]!,
          originals.length == 1 ? first.phase : 'Общее состояние',
          descriptions.join('; '),
          rules.length == 1 ? rules.single : null,
        ),
      );
    }
    final transitions = <(int, int), Transition>{};
    for (final block in order) {
      for (final t in edges[block] ?? <Transition>[]) {
        final next = Transition(
          remap[block]!,
          t.read,
          remap[t.to]!,
          t.write,
          t.move,
        );
        transitions[(next.from, next.read)] = next;
      }
    }
    return TuringMachine(
      inputAlphabet: machine.inputAlphabet,
      wordAlphabet: machine.wordAlphabet,
      states: states,
      transitions: transitions,
      initial: remap[blocks[machine.initial]]!,
      halts: {for (final block in haltBlocks) remap[block]!},
    );
  }
}
