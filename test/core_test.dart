import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:markov_turing_studio/domain/parser.dart';
import 'package:markov_turing_studio/domain/turing.dart';
import 'package:markov_turing_studio/compiler/machine_builder.dart';
import 'package:markov_turing_studio/compiler/markov_compiler.dart';
import 'package:markov_turing_studio/execution/limits.dart';
import 'package:markov_turing_studio/execution/markov_interpreter.dart';
import 'package:markov_turing_studio/execution/turing_simulator.dart';
import 'package:markov_turing_studio/execution/verification.dart';
import 'package:markov_turing_studio/storage/project.dart';
import 'package:markov_turing_studio/storage/project_repository.dart';

void main() {
  final parser = MarkovParser(),
      compiler = MarkovToTuringCompiler(),
      verifier = EquivalenceVerifier();
  const limits = ExecutionLimits(
    markovSteps: 200,
    turingSteps: 300000,
    milliseconds: 10000,
    history: 0,
  );
  test(
    'only sigma at start, lambda tail, no right delimiter on any transition',
    () {
      final p = parser.parse('01 -> 10', '01');
      final m = compiler.compile(p);
      final tape = WordTapeCodec.encode(m, '0011');
      expect(tape.cells.length, 5);
      expect(tape.read(0), TapeSymbol.left);
      expect(tape.read(5), TapeSymbol.blank);
      expect(TapeSymbol.label(TapeSymbol.left), 'σ');
      expect(TapeSymbol.label(TapeSymbol.blank), 'λ');
      expect(
        m.transitions.values.every((t) => t.read != -3 && t.write != -3),
        true,
      );
      final sim = TuringMachineSimulator(m, tape, head: 0)..run();
      expect(sim.status, ExecutionStatus.halted);
      expect(WordTapeCodec.decode(m, sim.tape), '1100');
      expect(sim.tape.cells.length, 5);
    },
  );
  group('Parser', () {
    test('all syntax, order, lines, alphabet extension', () {
      final p = parser.parse('// test\n0 -> 1\n1 ->. 2\n2 ->\n-> a', '01');
      expect(p.rules.length, 4);
      expect(p.rules.first.line, 2);
      expect(p.rules[1].terminal, true);
      expect(p.rules[2].right, isEmpty);
      expect(p.rules.last.left, isEmpty);
      expect(p.alphabet, contains(50));
    });
    for (final bad in [
      'a b',
      '0 -> 1 -> 0',
      '0 -> . 1',
      '0 ->.. 1',
      'a b -> c',
    ]) {
      test(
        'reject $bad',
        () => expect(() => parser.parse(bad, '01'), throwsFormatException),
      );
    }
    test('empty program valid, empty alphabet invalid', () {
      expect(parser.parse('', '01').rules, isEmpty);
      expect(() => parser.parse('', ''), throwsFormatException);
    });
  });
  group('Markov semantics', () {
    test('rule priority precedes position', () {
      final s = MarkovInterpreter(
        parser.parse('00 ->. 2\n11 ->. 3', '01'),
        '1100',
      )..run();
      expect(s.word, '112');
      expect(s.history.single.position, 2);
    });
    test('leftmost overlapping match', () {
      final s = MarkovInterpreter(parser.parse('00 ->. 1', '01'), '000')..run();
      expect(s.word, '10');
    });
    test('restart from first rule', () {
      final s = MarkovInterpreter(parser.parse('0 ->. 2\n1 -> 0', '01'), '1')
        ..run();
      expect(s.word, '2');
      expect(s.steps, 2);
    });
    test('limit is not halt; history bounded', () {
      final s = MarkovInterpreter(
        parser.parse('0 -> 0', '01'),
        '0',
        limits: const ExecutionLimits(markovSteps: 7, history: 2),
      )..run();
      expect(s.status, ExecutionStatus.limited);
      expect(s.steps, 7);
      expect(s.history.length, 2);
    });
    test('word-length limit and explicit stop', () {
      final s = MarkovInterpreter(
        parser.parse('0 -> 00', '01'),
        '0',
        limits: const ExecutionLimits(maxWordLength: 3),
      )..run();
      expect(s.word, '000');
      expect(s.status, ExecutionStatus.limited);
      final stopped = MarkovInterpreter(parser.parse('0 -> 0', '01'), '0')
        ..stop();
      expect(stopped.step(), isNull);
      expect(stopped.status, ExecutionStatus.stopped);
    });
    test('exact step budget still allows exhaustion detection', () {
      final s = MarkovInterpreter(
        parser.parse('0 ->', '01'),
        '0',
        limits: const ExecutionLimits(markovSteps: 1),
      )..run();
      expect(s.status, ExecutionStatus.halted);
    });
  });
  group('Builder and generic simulator', () {
    test('reject transition conflicts and unknown states', () {
      final b = TuringMachineBuilder();
      final a = b.state('test', 'test');
      b.add(a, 0, a, 0, Direction.stay);
      expect(() => b.add(a, 0, a, 1, Direction.left), throwsStateError);
      expect(() => b.add(a, 1, 99, 1, Direction.left), throwsStateError);
    });
    test('tape expands both directions and erases blank', () {
      final tape = SparseTape()
        ..write(-100, 48)
        ..write(100, 49);
      expect(tape.read(-100), 48);
      expect(tape.read(0), TapeSymbol.blank);
      tape.write(-100, TapeSymbol.blank);
      expect(tape.cells.containsKey(-100), false);
    });
    test('handbuilt machine visits negative coordinates', () {
      final b = TuringMachineBuilder();
      final start = b.state('test', 'left'),
          next = b.state('test', 'write'),
          halt = b.state('halt', 'done');
      b.add(start, -1, next, 48, Direction.left);
      b.add(next, -1, halt, 49, Direction.stay);
      final machine = b.build([], [], start, {halt});
      final s = TuringMachineSimulator(machine, SparseTape())..run();
      expect(s.head, -1);
      expect(s.tape.read(-1), 49);
      expect(s.status, ExecutionStatus.halted);
    });
    test('undefined transitions fail explicitly', () {
      final b = TuringMachineBuilder();
      final start = b.state('test', 'missing');
      final s = TuringMachineSimulator(b.build([], [], start, {}), SparseTape())
        ..run();
      expect(s.status, ExecutionStatus.error);
    });
    test('tape-cell budget prevents unbounded allocation', () {
      final b = TuringMachineBuilder();
      final q = b.state('grow', 'grow');
      b.add(q, TapeSymbol.blank, q, 48, Direction.right);
      final s = TuringMachineSimulator(
        b.build([], [], q, {}),
        SparseTape(),
        limits: const ExecutionLimits(maxCells: 3),
      )..run();
      expect(s.status, ExecutionStatus.limited);
      expect(s.tape.cells.length, 3);
    });
    test('compiler budget is explicit', () {
      final b = TuringMachineBuilder(maxStates: 1);
      b.state('test', 'one');
      expect(
        () => b.state('test', 'two'),
        throwsA(isA<CompilationException>()),
      );
    });
  });
  group('Compiler differential exhaustive tests', () {
    final programs = <String>[
      '',
      '0 ->. 1',
      '01 -> 10',
      '0 ->',
      '->. 1',
      '00 -> 1\n11 ->. 0',
      '01 ->. 1011',
      '001 ->. 1',
      '0 ->.',
      '00 ->. 11111',
      '->.',
      '101 ->. 0',
      '00 ->. 1',
      '0 ->. 00',
      '1 ->. 000',
      '0 ->. 2\n1 -> 0',
      '01 -> 1\n10 -> 0\n0 ->. 1',
      '010 ->. 11',
    ];
    for (final source in programs) {
      test('all 63 binary inputs: ${source.replaceAll('\n', '; ')}', () {
        final p = parser.parse(source, '01');
        final m = compiler.compile(p);
        expect(m.transitions.keys.toSet().length, m.transitions.length);
        for (final word in verifier.words(p.inputAlphabet, 5)) {
          final result = verifier.verify(p, m, word, limits: limits);
          expect(
            result.verdict,
            Verdict.match,
            reason: 'input=$word; ${result.detail}',
          );
        }
      });
    }
    test('every short single terminal substitution and every input', () {
      final words = verifier.words([48, 49], 3).toList();
      var count = 0;
      for (final lhs in words) {
        for (final rhs in words) {
          final p = parser.parse('$lhs ->. $rhs', '01');
          final m = compiler.compile(p);
          for (final input in words) {
            final result = verifier.verify(p, m, input, limits: limits);
            expect(
              result.verdict,
              Verdict.match,
              reason: '$lhs ->. $rhs on $input',
            );
            count++;
          }
        }
      }
      expect(count, 3375);
    });
    test('all short length-decreasing ordinary substitutions', () {
      final words = verifier.words([48, 49], 3).toList();
      var checked = 0;
      for (final lhs in words.where((w) => w.isNotEmpty)) {
        for (final rhs in words.where((w) => w.length < lhs.length)) {
          final p = parser.parse('$lhs -> $rhs', '01');
          final m = compiler.compile(p);
          for (final input in words) {
            expect(
              verifier.verify(p, m, input, limits: limits).verdict,
              Verdict.match,
              reason: '$lhs -> $rhs on $input',
            );
            checked++;
          }
        }
      }
      expect(checked, 1050);
    });
    test('auxiliary marker scans the whole word before terminal deletion', () {
      final p = parser.parse('a0 -> 0a\na1 -> 1a\na ->.\n-> a', '01');
      final m = compiler.compile(p);
      for (final input in verifier.words(p.inputAlphabet, 5)) {
        final result = verifier.verify(p, m, input, limits: limits);
        expect(result.verdict, Verdict.match);
        expect(result.turingWord, input);
      }
    });
    test('random terminating multi-rule programs', () {
      final rng = Random(4101);
      final words = verifier.words([48, 49], 3).toList();
      for (var n = 0; n < 100; n++) {
        final source = [
          for (var k = 0; k < 3; k++)
            '${words[1 + rng.nextInt(words.length - 1)]} ->. ${words[rng.nextInt(words.length)]}',
        ].join('\n');
        final p = parser.parse(source, '01');
        final m = compiler.compile(p);
        for (final input in words) {
          expect(
            verifier.verify(p, m, input, limits: limits).verdict,
            Verdict.match,
            reason: '$source on $input',
          );
        }
      }
    });
    test('technical-looking user symbols and Unicode remain distinct', () {
      for (final source in ['# ->. \$□', '😀 ->. 🐱😀', '⊢ ->. ⊣']) {
        final sigma = source.split(' ->. ').first;
        final p = parser.parse(source, sigma);
        final m = compiler.compile(p);
        expect(
          verifier.verify(p, m, sigma, limits: limits).verdict,
          Verdict.match,
        );
      }
    });
    test('loops and growth are inconclusive', () {
      for (final source in ['0 -> 0', '-> 1', '0 -> 00']) {
        final p = parser.parse(source, '01');
        final m = compiler.compile(p);
        final result = verifier.verify(
          p,
          m,
          '0',
          limits: const ExecutionLimits(
            markovSteps: 10,
            turingSteps: 5000,
            maxCells: 40,
            history: 0,
          ),
        );
        expect(result.verdict, Verdict.inconclusive);
      }
    });
    test('one-sided limits never claim equivalence', () {
      final p = parser.parse('0 ->. 1', '01');
      final m = compiler.compile(p);
      expect(
        verifier
            .verify(p, m, '0', limits: const ExecutionLimits(turingSteps: 1))
            .verdict,
        Verdict.inconclusive,
      );
    });
    test('machine survives export without compiler/interpreter access', () {
      final p = parser.parse('01 ->. 110', '01');
      final exported = jsonDecode(
        jsonEncode(compiler.compile(p).toJson()),
      ) as Map<String, dynamic>;
      final transitions = <(int, int), Transition>{};
      int q(dynamic s) =>
          (exported['states'] as List).firstWhere(
                (state) => state['id'] == s,
              )['internalId']
              as int;
      for (final t in exported['transitions'] as List) {
        final transition = Transition(
          q(t['state']),
          t['read'] as int,
          q(t['nextState']),
          t['write'] as int,
          {
            'L': Direction.left,
            'R': Direction.right,
            '—': Direction.stay,
          }[t['move']]!,
        );
        transitions[(transition.from, transition.read)] = transition;
      }
      final m = TuringMachine(
        inputAlphabet: [48, 49],
        wordAlphabet: [48, 49],
        states: [
          for (var i = 0; i < (exported['states'] as List).length; i++)
            StateInfo(i, '', '', null),
        ],
        transitions: transitions,
        initial: q(exported['initial']),
        halts: {for (final h in exported['halts'] as List) q(h)},
      );
      final s = TuringMachineSimulator(
        m,
        WordTapeCodec.encode(m, '001'),
        head: 0,
      )..run();
      expect(s.status, ExecutionStatus.halted);
      expect(WordTapeCodec.decode(m, s.tape), '0110');
    });
    test(
      'batch budget rejects explosive enumeration',
      () => expect(
        () => verifier.words([48, 49, 50, 51, 52], 8).toList(),
        throwsArgumentError,
      ),
    );
  });
  group('Local projects', () {
    test('roundtrip, serialized autosave and recovery from damaged newest snapshot', () async {
      final dir = await Directory.systemTemp.createTemp('markov_test_');
      addTearDown(() => dir.delete(recursive: true));
      final repo = ProjectRepository(dir), p = StudioProject.fresh(1);
      await repo.save([p], p.id);
      p.name = 'Второй';
      final a = repo.save([p], p.id);
      p.name = 'Третий';
      final b = repo.save([p], p.id);
      await Future.wait([a, b]);
      expect(
        (await ProjectRepository(dir).load()).projects.single.name,
        'Третий',
      );
      await File('${dir.path}/workspace_b.json').writeAsString('corrupt');
      final recovered = await ProjectRepository(dir).load();
      expect(recovered.projects.single.name, 'Второй');
      expect(recovered.selected, p.id);
    });
    test(
      'foreign project formats rejected',
      () => expect(
        () => StudioProject.fromJson({'version': 99}),
        throwsFormatException,
      ),
    );
  });
}
