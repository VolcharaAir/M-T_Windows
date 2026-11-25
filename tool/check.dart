import 'dart:convert';
import 'dart:io';

import 'package:markov_turing_studio/compiler/markov_compiler.dart';
import 'package:markov_turing_studio/domain/parser.dart';
import 'package:markov_turing_studio/execution/verification.dart';

/// Standalone demonstration: no Flutter, UI, Python, network or server required.
void main(List<String> arguments) {
  final source = arguments.isEmpty
      ? '01 -> 10\n11 ->. 0'
      : File(arguments.first).readAsStringSync();
  final program = MarkovParser().parse(
    source,
    arguments.length > 1 ? arguments[1] : '01',
  );
  final machine = MarkovToTuringCompiler().compile(program);
  final verifier = EquivalenceVerifier();
  var matches = 0, mismatches = 0, inconclusive = 0;
  for (final input in verifier.words(program.inputAlphabet, 5)) {
    final result = verifier.verify(program, machine, input);
    switch (result.verdict) {
      case Verdict.match:
        matches++;
      case Verdict.mismatch:
        mismatches++;
        stdout.writeln('Расхождение на «$input»: ${result.detail}');
      case Verdict.inconclusive:
        inconclusive++;
    }
  }
  stdout.writeln(
    jsonEncode({
      'states': machine.states.length,
      'transitions': machine.transitions.length,
      'matches': matches,
      'mismatches': mismatches,
      'inconclusive': inconclusive,
    }),
  );
  if (arguments.length > 2) {
    File(arguments[2]).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(machine.toJson()),
    );
  }
  if (mismatches > 0) exitCode = 1;
}
