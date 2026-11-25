// Дополнительные регрессионные проверки М&T 1.5.
// Запуск из каталога проекта: flutter test test/extra_regression_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:markov_turing_studio/compiler/markov_compiler.dart';
import 'package:markov_turing_studio/domain/parser.dart';
import 'package:markov_turing_studio/domain/turing.dart';
import 'package:markov_turing_studio/execution/limits.dart';
import 'package:markov_turing_studio/execution/turing_simulator.dart';
import 'package:markov_turing_studio/execution/verification.dart';

void main() {
  final parser = MarkovParser();
  final compiler = MarkovToTuringCompiler();
  final verifier = EquivalenceVerifier();
  const limits = ExecutionLimits(
    markovSteps: 100,
    turingSteps: 120000,
    maxCells: 4096,
    milliseconds: 20000,
    history: 0,
  );

  void checkWord(String source, String alphabet, String input, String expected) {
    final p = parser.parse(source, alphabet);
    final m = compiler.compile(p);
    final s = TuringMachineSimulator(
      m, WordTapeCodec.encode(m, input), limits: limits,
    )..run();
    expect(s.status, ExecutionStatus.halted,
        reason: '$source on "$input" failed to terminate');
    expect(WordTapeCodec.decode(m, s.tape), expected,
        reason: '$source on "$input"');
    final verification = verifier.verify(p, m, input, limits: limits);
    expect(verification.verdict, Verdict.match,
        reason: '$source on "$input": ${verification.detail}');
  }

  group('One-pass optimized compilation', () {
    for (final entry in [
      ('1 -> 0', '01', '1111', '0000'),
      ('0 -> 1', '01', '10010100', '11111111'),
      ('a -> b', 'abc', 'aacaba', 'bbcbbb'),
      ('1 -> 0', '012', '12120', '02020'),
    ]) {
      test('smallest supported table ${entry.$1} alphabet ${entry.$2}', () {
        final p = parser.parse(entry.$1, entry.$2);
        final m = compiler.compile(p);
        expect(m.stateName(m.initial), 'S_1');
        expect(m.states.length - m.halts.length, 2);
        expect(m.transitions.length, p.alphabet.length + 2);
        expect(m.halts.length, 1);
        expect(m.stateName(m.halts.single), 'STOP');
        expect(m.transitions.keys.where((k) => k.$2 == TapeSymbol.left).length, 1);
        expect(m.transitions.values.any((t) => t.read == TapeSymbol.blank &&
            m.halts.contains(t.to)), isTrue);
        checkWord(entry.$1, entry.$2, entry.$3, entry.$4);
      });
    }
    test('every binary input length <= 8 for 1 -> 0', () {
      final p = parser.parse('1 -> 0', '01');
      final m = compiler.compile(p);
      for (final word in verifier.words(p.inputAlphabet, 8)) {
        final sim = TuringMachineSimulator(
          m, WordTapeCodec.encode(m, word), limits: limits,
        )..run();
        expect(sim.status, ExecutionStatus.halted, reason: word);
        expect(WordTapeCodec.decode(m, sim.tape), word.replaceAll('1', '0'));
        expect(sim.steps, word.runes.length + 2);
      }
    });
    test('three-symbol alphabet exhaustive length <= 5', () {
      final p = parser.parse('a -> b', 'abc');
      final m = compiler.compile(p);
      for (final word in verifier.words(p.inputAlphabet, 5)) {
        final sim = TuringMachineSimulator(
          m, WordTapeCodec.encode(m, word), limits: limits,
        )..run();
        expect(sim.status, ExecutionStatus.halted, reason: word);
        expect(WordTapeCodec.decode(m, sim.tape), word.replaceAll('a', 'b'));
      }
    });
  });

  group('Universal compilation must preserve Markov semantics', () {
    for (final entry in [
      ('1 ->. 0', '01', '1111', '0111'), // Терминальное: ровно один раз.
      ('11 -> 0', '01', '1111', '00'),
      ('01 -> 10', '01', '0101', '1100'),
      ('00 ->. 1\n11 ->. 0', '01', '1100', '111'), // Приоритет правил.
      ('1 -> 0\n0 ->. 2', '01', '11', '20'),
      ('a -> λ', 'ab', 'abaa', 'b'),
      ('λ ->. x', 'ab', 'ab', 'xab'),
      ('😀 -> 🐱', '😀a', '😀a😀', '🐱a🐱'),
      ('', '01', '101001', '101001'),
    ]) {
      test('exact result: ${entry.$1.replaceAll('\n', '; ')}', () {
        checkWord(entry.$1, entry.$2, entry.$3, entry.$4);
      });
    }
    test('priority/overlap: compare every binary word up to length 6', () {
      final p = parser.parse('00 -> 1\n11 ->. 0\n01 ->. 1011', '01');
      final m = compiler.compile(p);
      expect(m.stateName(m.initial), 'S_1');
      for (final word in verifier.words(p.inputAlphabet, 6)) {
        final result = verifier.verify(p, m, word, limits: limits);
        expect(result.verdict, Verdict.match,
          reason: '$word: ${result.detail}');
      }
    });
    test('identity and alternating rules must not fake termination', () {
      for (final source in ['1 -> 1', '1 -> 0\n0 -> 1']) {
        final p = parser.parse(source, '01');
        final m = compiler.compile(p);
        final result = verifier.verify(p, m, '1',
          limits: const ExecutionLimits(
            markovSteps: 10, turingSteps: 3000,
            maxCells: 400, milliseconds: 20000, history: 0,
          ));
        expect(result.verdict, Verdict.inconclusive, reason: source);
        expect(result.markovStatus, ExecutionStatus.limited);
        expect(result.turingStatus, isNot(ExecutionStatus.halted));
      }
    });
    test('reserved tape symbols not accepted as user symbols', () {
      expect(() => parser.parse('a -> b', 'aσ'), throwsFormatException);
      expect(() => parser.parse('a -> b', 'aλ'), throwsFormatException);
      expect(() => parser.parse('a -> σ', 'ab'), throwsFormatException);
      expect(() => parser.parse('aλ -> b', 'ab'), throwsFormatException);
    });
  });
}
