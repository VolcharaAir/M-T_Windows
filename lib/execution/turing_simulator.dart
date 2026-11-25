import 'dart:collection';

import '../domain/markov.dart';
import '../domain/turing.dart';
import 'limits.dart';

/// Generic two-way sparse tape. Unwritten cells are always blank.
class SparseTape {
  final Map<int, int> cells = {};
  int read(int position) => cells[position] ?? TapeSymbol.blank;
  void write(int position, int symbol) {
    if (symbol == TapeSymbol.blank) {
      cells.remove(position);
    } else {
      cells[position] = symbol;
    }
  }
}

class TuringStep {
  final int number, head;
  final Transition transition;
  const TuringStep(this.number, this.head, this.transition);
}

/// Executes only δ, head, state and tape. No Markov objects or callbacks.
class TuringMachineSimulator {
  final TuringMachine machine;
  final ExecutionLimits limits;
  final SparseTape tape;
  final Queue<TuringStep> history = Queue();
  final Stopwatch _clock = Stopwatch();
  int state, head, steps = 0;
  ExecutionStatus status = ExecutionStatus.ready;
  String detail = '';
  TuringMachineSimulator(
    this.machine,
    this.tape, {
    int? initialState,
    this.head = 0,
    this.limits = const ExecutionLimits(),
  }) : state = initialState ?? machine.initial {
    if (tape.cells.length > limits.maxCells) {
      status = ExecutionStatus.limited;
      detail = 'Размер ленты';
    } else if (machine.halts.contains(state)) {
      status = ExecutionStatus.halted;
      detail = machine.states[state].description;
    }
  }
  bool get active =>
      status == ExecutionStatus.ready || status == ExecutionStatus.running;
  void pause() => _clock.stop();
  void stop() {
    if (active) status = ExecutionStatus.stopped;
    _clock.stop();
  }

  TuringStep? step() {
    if (!active) return null;
    _clock.start();
    if (steps >= limits.turingSteps ||
        _clock.elapsedMilliseconds >= limits.milliseconds) {
      status = ExecutionStatus.limited;
      detail = 'Число переходов или время вычисления';
      _clock.stop();
      return null;
    }
    final t = machine.transitions[(state, tape.read(head))];
    if (t == null) {
      status = ExecutionStatus.error;
      detail =
          'Не определён переход δ(q$state, ${TapeSymbol.label(tape.read(head))})';
      _clock.stop();
      return null;
    }
    if (t.write != TapeSymbol.blank &&
        tape.read(head) == TapeSymbol.blank &&
        tape.cells.length >= limits.maxCells) {
      status = ExecutionStatus.limited;
      detail = 'Размер ленты';
      _clock.stop();
      return null;
    }
    final event = TuringStep(++steps, head, t);
    tape.write(head, t.write);
    head += switch (t.move) {
      Direction.left => -1,
      Direction.right => 1,
      Direction.stay => 0,
    };
    state = t.to;
    if (limits.history > 0) {
      history.add(event);
      if (history.length > limits.history) history.removeFirst();
    }
    status = machine.halts.contains(state)
        ? ExecutionStatus.halted
        : ExecutionStatus.running;
    if (status == ExecutionStatus.halted) {
      detail = machine.states[state].description;
      _clock.stop();
    }
    return event;
  }

  void run() {
    while (active) {
      step();
    }
  }
}

/// Representation adapter belongs outside the generic simulator.
abstract final class WordTapeCodec {
  static SparseTape encode(TuringMachine machine, String input) {
    final word = symbols(input);
    if (word.any((s) => !machine.inputAlphabet.contains(s))) {
      throw const FormatException('Входное слово содержит символ вне алфавита');
    }
    final tape = SparseTape()..write(0, TapeSymbol.left);
    for (var i = 0; i < word.length; i++) {
      tape.write(i + 1, word[i]);
    }
    return tape;
  }

  static String decode(TuringMachine machine, SparseTape tape) {
    if (tape.read(0) != TapeSymbol.left) {
      throw StateError('Повреждён маркер начала σ');
    }
    final word = <int>[];
    for (var i = 1; i <= tape.cells.length; i++) {
      final s = tape.read(i);
      if (s == TapeSymbol.blank) {
        if (tape.cells.length != word.length + 1) {
          throw StateError('Лишние символы вне слова');
        }
        return wordText(word);
      }
      if (!machine.wordAlphabet.contains(s)) {
        throw StateError('Лента содержит служебные символы');
      }
      word.add(s);
    }
    throw StateError('Нарушено представление слова');
  }
}
