import 'dart:collection';

import '../domain/markov.dart';
import 'limits.dart';

class MarkovStep {
  final int number, rule, line, position;
  final String before, after;
  final bool terminal;
  MarkovStep(
    this.number,
    this.rule,
    this.line,
    this.position,
    this.before,
    this.after,
    this.terminal,
  );
}

class MarkovInterpreter {
  final MarkovProgram program;
  final ExecutionLimits limits;
  List<int> _word;
  final Queue<MarkovStep> history = Queue();
  final Stopwatch _clock = Stopwatch();
  ExecutionStatus status = ExecutionStatus.ready;
  int steps = 0;
  String detail = '';
  MarkovInterpreter(
    this.program,
    String input, {
    this.limits = const ExecutionLimits(),
  }) : _word = symbols(input) {
    program.validateInput(input);
    if (_word.length > limits.maxWordLength) {
      status = ExecutionStatus.limited;
      detail = 'Длина входного слова';
    }
  }
  String get word => wordText(_word);
  bool get active =>
      status == ExecutionStatus.ready || status == ExecutionStatus.running;
  void stop() {
    if (active) status = ExecutionStatus.stopped;
    _clock.stop();
  }

  void pause() => _clock.stop();
  MarkovStep? step() {
    if (!active) return null;
    _clock.start();
    if (_clock.elapsedMilliseconds >= limits.milliseconds) {
      status = ExecutionStatus.limited;
      detail = 'Время вычисления';
      _clock.stop();
      return null;
    }
    for (final rule in program.rules) {
      var position = -1;
      for (var i = 0; i <= _word.length - rule.left.length; i++) {
        var matches = true;
        for (var j = 0; j < rule.left.length; j++) {
          if (_word[i + j] != rule.left[j]) {
            matches = false;
            break;
          }
        }
        if (matches) {
          position = i;
          break;
        }
      }
      if (position < 0) continue;
      if (steps >= limits.markovSteps ||
          _word.length - rule.left.length + rule.right.length >
              limits.maxWordLength) {
        status = ExecutionStatus.limited;
        detail = 'Число подстановок или длина слова';
        _clock.stop();
        return null;
      }
      final before = word;
      _word = [
        ..._word.take(position),
        ...rule.right,
        ..._word.skip(position + rule.left.length),
      ];
      steps++;
      final event = MarkovStep(
        steps,
        rule.id,
        rule.line,
        position,
        before,
        word,
        rule.terminal,
      );
      if (limits.history > 0) {
        history.add(event);
        if (history.length > limits.history) history.removeFirst();
      }
      status = rule.terminal ? ExecutionStatus.halted : ExecutionStatus.running;
      if (rule.terminal) {
        detail = 'Заключительное правило ${rule.id}';
        _clock.stop();
      }
      return event;
    }
    status = ExecutionStatus.halted;
    detail = 'Нет применимого правила';
    _clock.stop();
    return null;
  }

  void run() {
    while (active) {
      step();
    }
  }
}
