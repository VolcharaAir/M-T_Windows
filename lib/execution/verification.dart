import '../domain/markov.dart';
import '../domain/turing.dart';
import 'limits.dart';
import 'markov_interpreter.dart';
import 'turing_simulator.dart';

enum Verdict { match, mismatch, inconclusive }

class VerificationResult {
  final String input, markovWord;
  final String? turingWord;
  final ExecutionStatus markovStatus, turingStatus;
  final int markovSteps, turingSteps;
  final Verdict verdict;
  final String detail;
  const VerificationResult(
    this.input,
    this.markovWord,
    this.turingWord,
    this.markovStatus,
    this.turingStatus,
    this.markovSteps,
    this.turingSteps,
    this.verdict,
    this.detail,
  );
}

class EquivalenceVerifier {
  VerificationResult verify(
    MarkovProgram program,
    TuringMachine machine,
    String input, {
    ExecutionLimits limits = const ExecutionLimits(),
  }) {
    final markov = MarkovInterpreter(program, input, limits: limits)..run();
    final turing = TuringMachineSimulator(
      machine,
      WordTapeCodec.encode(machine, input),
      head: 0,
      limits: limits,
    )..run();
    String? output;
    String detail = '';
    if (turing.status == ExecutionStatus.halted) {
      try {
        output = WordTapeCodec.decode(machine, turing.tape);
      } catch (e) {
        detail = e.toString();
      }
    }
    final bothHalted =
        markov.status == ExecutionStatus.halted &&
        turing.status == ExecutionStatus.halted;
    final verdict =
        turing.status == ExecutionStatus.error ||
            (bothHalted && output != markov.word)
        ? Verdict.mismatch
        : bothHalted
        ? Verdict.match
        : Verdict.inconclusive;
    return VerificationResult(
      input,
      markov.word,
      output,
      markov.status,
      turing.status,
      markov.steps,
      turing.steps,
      verdict,
      detail.isNotEmpty ? detail : '${markov.detail}; ${turing.detail}',
    );
  }

  Iterable<String> words(List<int> alphabet, int maxLength) sync* {
    if (maxLength < 0 || maxLength > 8) {
      throw ArgumentError('Длина должна быть от 0 до 8');
    }
    var count = 1, level = 1;
    for (var i = 1; i <= maxLength; i++) {
      level *= alphabet.length;
      count += level;
    }
    if (count > 10000) throw ArgumentError('Набор превышает 10 000 слов');
    yield '';
    var current = <String>[''];
    for (var length = 1; length <= maxLength; length++) {
      current = [
        for (final prefix in current)
          for (final s in alphabet) prefix + wordText([s]),
      ];
      yield* current;
    }
  }
}
