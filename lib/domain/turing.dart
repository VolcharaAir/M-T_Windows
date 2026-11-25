import 'markov.dart';

/// Negative symbol IDs are disjoint from Unicode user symbols, including #, $, □.
abstract final class TapeSymbol {
  static const blank = -1, left = -2;
  static int anchor(int symbol) => -symbol - 10;
  static bool isAnchor(int symbol) => symbol <= -8;
  static int unanchor(int symbol) => -symbol - 10;
  static String label(int symbol) => switch (symbol) {
    blank => 'λ',
    left => 'σ',
    _ => isAnchor(symbol) ? '⟦${label(unanchor(symbol))}⟧' : wordText([symbol]),
  };
}

enum Direction { left, right, stay }

String directionLabel(Direction d) => switch (d) {
  Direction.left => 'L',
  Direction.right => 'R',
  Direction.stay => 'S',
};

class StateInfo {
  final int id;
  final String phase, description;
  final int? rule;
  const StateInfo(this.id, this.phase, this.description, this.rule);
  String get name => 'q$id';
}

class Transition {
  final int from, read, to, write;
  final Direction move;
  const Transition(this.from, this.read, this.to, this.write, this.move);
  Map<String, dynamic> toJson() => {
    'state': 'q$from',
    'read': read,
    'nextState': 'q$to',
    'write': write,
    'move': directionLabel(move),
  };
}

class TuringMachine {
  final List<int> inputAlphabet, wordAlphabet;
  final List<StateInfo> states;
  final Map<(int, int), Transition> transitions;
  final int initial;
  final Set<int> halts;
  TuringMachine({
    required Iterable<int> inputAlphabet,
    required Iterable<int> wordAlphabet,
    required Iterable<StateInfo> states,
    required Map<(int, int), Transition> transitions,
    required this.initial,
    required Set<int> halts,
  }) : inputAlphabet = List.unmodifiable(inputAlphabet),
       wordAlphabet = List.unmodifiable(wordAlphabet),
       states = List.unmodifiable(states),
       transitions = Map.unmodifiable(transitions),
       halts = Set.unmodifiable(halts);
  Set<int> get tapeAlphabet => {
    TapeSymbol.blank,
    TapeSymbol.left,
    ...wordAlphabet,
    for (final t in transitions.values) ...[t.read, t.write],
  };
  String stateName(int id) {
    if (!halts.contains(id)) return 'S_${id + 1}';
    if (halts.length == 1) return 'STOP';
    final sorted = halts.toList()..sort();
    return 'STOP${sorted.indexOf(id) + 1}';
  }

  Map<String, dynamic> toJson() => {
    'format': 'markov-turing-machine',
    'version': 3,
    'initial': stateName(initial),
    'halts': halts.map(stateName).toList(),
    'blank': TapeSymbol.blank,
    'left': TapeSymbol.left,
    'inputAlphabet': inputAlphabet,
    'wordAlphabet': wordAlphabet,
    'symbols': {for (final s in tapeAlphabet) '$s': TapeSymbol.label(s)},
    'states': states
        .map(
          (s) => {
            'id': stateName(s.id),
            'internalId': s.id,
            'phase': s.phase,
            'description': s.description,
            'rule': s.rule,
          },
        )
        .toList(),
    'transitions': transitions.values
        .map(
          (t) => {
            'state': stateName(t.from),
            'read': t.read,
            'nextState': stateName(t.to),
            'write': t.write,
            'move': t.move == Direction.stay ? '—' : directionLabel(t.move),
          },
        )
        .toList(),
    'initialHead': 0,
  };
}
