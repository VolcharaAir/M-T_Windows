import 'dart:convert';
import 'dart:io';

import 'package:markov_turing_studio/compiler/markov_compiler.dart';
import 'package:markov_turing_studio/domain/parser.dart';
import 'package:markov_turing_studio/domain/turing.dart';
import 'package:markov_turing_studio/execution/turing_simulator.dart';

/// Prints and executes the very same compiled transition table.
void main() {
  final program = MarkovParser().parse('1 -> 0', '01');
  final machine = MarkovToTuringCompiler().compile(program);
  stdout.writeln(
    'Working states: ${machine.states.length - machine.halts.length}',
  );
  stdout.writeln('Transitions: ${machine.transitions.length}');
  for (final t in machine.transitions.values) {
    stdout.writeln(
      '${machine.stateName(t.from)} ${TapeSymbol.label(t.read)} -> '
      '${TapeSymbol.label(t.write)} '
      '${t.move == Direction.stay ? '—' : directionLabel(t.move)} '
      '${machine.stateName(t.to)}',
    );
  }
  for (final input in ['1111', '101010', '000', '']) {
    final runner = TuringMachineSimulator(
      machine,
      WordTapeCodec.encode(machine, input),
    );
    final trace = <String>[];
    while (runner.active) {
      final step = runner.step();
      if (step != null) {
        final t = step.transition;
        if (!identical(t, machine.transitions[(t.from, t.read)])) {
          throw StateError('Simulator did not execute the listed table');
        }
        trace.add(
          '${machine.stateName(t.from)}@${step.head}:${TapeSymbol.label(t.read)}',
        );
      }
    }
    stdout.writeln(
      'Input: "$input"; output: "${WordTapeCodec.decode(machine, runner.tape)}"; '
      'status: ${runner.status.name}; transitions: ${runner.steps}; head: ${runner.head}',
    );
    stdout.writeln('Executed: ${trace.join(' → ')}');
  }
  File('docs/optimized-machine.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(machine.toJson()),
  );
}
