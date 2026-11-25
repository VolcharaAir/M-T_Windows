import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:markov_turing_studio/compiler/markov_compiler.dart';
import 'package:markov_turing_studio/compiler/machine_optimizer.dart';
import 'package:markov_turing_studio/compiler/machine_builder.dart';
import 'package:markov_turing_studio/domain/parser.dart';
import 'package:markov_turing_studio/domain/turing.dart';
import 'package:markov_turing_studio/execution/turing_simulator.dart';
import 'package:markov_turing_studio/execution/verification.dart';
import 'package:markov_turing_studio/execution/limits.dart';

void main() {
  final parser = MarkovParser(),
      compiler = MarkovToTuringCompiler(),
      verifier = EquivalenceVerifier();
  test(
    'exact four transitions, two working states and sigma start for all inputs',
    () {
      final p = parser.parse('1 -> 0', '01'), m = compiler.compile(p);
      expect(m.stateName(m.initial), 'S_1');
      expect(m.states.length - m.halts.length, 2);
      expect(m.transitions.length, 4);
      expect(m.tapeAlphabet, {48, 49, TapeSymbol.left, TapeSymbol.blank});
      expect(m.halts.map(m.stateName), ['STOP']);
      final scan = m.transitions[(m.initial, TapeSymbol.left)]!.to;
      expect(m.stateName(scan), 'S_2');
      expect(m.transitions[(scan, 49)]!.write, 48);
      expect(m.transitions[(scan, 49)]!.to, scan);
      expect(m.transitions[(scan, 48)]!.write, 48);
      expect(
        m.halts.contains(m.transitions[(scan, TapeSymbol.blank)]!.to),
        true,
      );
      for (final input in ['1111', '101010', '000', '']) {
        final s = TuringMachineSimulator(m, WordTapeCodec.encode(m, input));
        expect(s.head, 0);
        s.step();
        expect(s.head, 1);
        expect(s.state, scan);
        s.run();
        expect(s.status, ExecutionStatus.halted);
        expect(WordTapeCodec.decode(m, s.tape), input.replaceAll('1', '0'));
        expect(s.steps, input.length + 2);
      }
    },
  );
  for (final pair in [
    ('0 -> 1', '01', '00100', '11111'),
    ('a -> b', 'abc', 'aaaca', 'bbbcb'),
    ('1 -> 0', '012', '12120', '02020'),
  ]) {
    test('generalization ${pair.$1} / ${pair.$2}', () {
      final p = parser.parse(pair.$1, pair.$2), m = compiler.compile(p);
      final s = TuringMachineSimulator(m, WordTapeCodec.encode(m, pair.$3))
        ..run();
      expect(s.status, ExecutionStatus.halted);
      expect(WordTapeCodec.decode(m, s.tape), pair.$4);
      expect(m.transitions.length, p.alphabet.length + 2);
      for (final input in verifier.words(p.inputAlphabet, 5)) {
        expect(verifier.verify(p, m, input).verdict, Verdict.match);
      }
    });
  }
  test('terminal, identity, deletion, multi-symbol and multiple rules use universal strategy', () {
    for (final source in [
      '1 ->. 0',
      '1 -> 1',
      '11 -> 0',
      '1 ->',
      '->. 1',
      '1 -> 0\n0 -> 1',
    ]) {
      final m = compiler.compile(parser.parse(source, '01'));
      expect(m.transitions.length, greaterThan(4), reason: source);
    }
    final p = parser.parse('11 -> 0', '01');
    expect(verifier.verify(p, compiler.compile(p), '1111').turingWord, '00');
    for (final source in ['1 -> 1', '1 -> 0\n0 -> 1']) {
      final p = parser.parse(source, '01'),
          r = verifier.verify(
            p,
            compiler.compile(p),
            '111',
            limits: const ExecutionLimits(markovSteps: 30, turingSteps: 3000),
          );
      expect(r.verdict, Verdict.inconclusive);
      expect(r.turingStatus, ExecutionStatus.limited);
    }
  });
  test('lambda deletion syntax and complex universal example', () {
    final p = parser.parse('ab -> ba\naa -> b\nb -> λ', 'ab');
    expect(p.rules.last.right, isEmpty);
    expect(p.alphabet.contains('λ'.runes.single), false);
    final machine = compiler.compile(p);
    for (final input in verifier.words(p.inputAlphabet, 5)) {
      expect(verifier.verify(p, machine, input).verdict, Verdict.match);
    }
    expect(() => parser.parse('a -> b', 'aλ'), throwsFormatException);
    expect(() => parser.parse('a -> σ', 'ab'), throwsFormatException);
  });
  test(
    'merge equivalent states; prune unreachable; preserve missing transitions',
    () {
      final b = TuringMachineBuilder(),
          start = b.state('s', 'start'),
          a = b.state('a', 'first'),
          c = b.state('c', 'second'),
          halt = b.state('h', 'done'),
          dead = b.state('d', 'unreachable');
      b.add(start, 48, a, 48, Direction.right);
      b.add(start, 49, c, 49, Direction.right);
      b.add(a, -1, halt, -1, Direction.stay);
      b.add(c, -1, halt, -1, Direction.stay);
      b.add(dead, 48, dead, 48, Direction.right);
      final m = MachineOptimizer().optimize(
        b.build([48, 49], [48, 49], start, {halt}),
      );
      expect(m.states.length, 3);
      expect(
        m.transitions[(m.initial, 48)]!.to,
        m.transitions[(m.initial, 49)]!.to,
      );
      expect(
        m.transitions.containsKey((m.transitions[(m.initial, 48)]!.to, 48)),
        false,
      );
      expect(m.states.any((s) => s.description.contains('unreachable')), false);
    },
  );
  test('seeded graph regression preserves every executed transition and head action', () {
    final rng = Random(9007), words = verifier.words([48, 49], 2).toList();
    const limits = ExecutionLimits(
      markovSteps: 30,
      turingSteps: 10000,
      milliseconds: 10000,
      history: 0,
      maxCells: 256,
    );
    for (var i = 0; i < 40; i++) {
      final source = [
        for (var j = 0; j < 2; j++)
          '${words[1 + rng.nextInt(words.length - 1)]} ->${rng.nextBool() ? '.' : ''} ${words[rng.nextInt(words.length)]}',
      ].join('\n');
      final p = parser.parse(source, '01'),
          raw = compiler.compileUniversal(p),
          m = compiler.compile(p);
      expect(m.initial, 0);
      expect(m.stateName(m.initial), 'S_1');
      final work = m.states.where((q) => !m.halts.contains(q.id)).toList();
      expect(work.map((s) => m.stateName(s.id)), [
        for (var n = 1; n <= work.length; n++) 'S_$n',
      ]);
      expect(m.states.length, lessThanOrEqualTo(raw.states.length));
      for (final input in verifier.words(p.inputAlphabet, 3)) {
        final a = TuringMachineSimulator(
              raw,
              WordTapeCodec.encode(raw, input),
              limits: limits,
            )..run(),
            b = TuringMachineSimulator(
              m,
              WordTapeCodec.encode(m, input),
              limits: limits,
            )..run();
        expect(b.status, a.status, reason: '$source / $input');
        expect(b.steps, a.steps);
        expect(b.head, a.head);
        expect(b.tape.cells, a.tape.cells);
      }
    }
  });
}
