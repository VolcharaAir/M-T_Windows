import 'package:material_ui/material_ui.dart';

import '../domain/parser.dart';
import '../execution/markov_interpreter.dart';
import '../execution/limits.dart';
import 'studio_controller.dart';
import 'execution_controls.dart';
import 'theme.dart';

String traceWord((String, String, String, ExecutionLimits) request) {
  final run = MarkovInterpreter(
    MarkovParser().parse(request.$1, request.$2),
    request.$3,
    limits: request.$4,
  )..run();
  final events = run.history.toList();
  final words = events.isEmpty
      ? [run.word]
      : [events.first.before, ...events.map((e) => e.after)];
  return '${words.map(shownWord).join(' → ')}\n${statusLabel(run.status)}';
}

class MarkovTrace extends StatelessWidget {
  final StudioController controller;
  const MarkovTrace({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final run = controller.markov;
    final events = run?.history.toList() ?? [];
    final words = events.isEmpty
        ? [run?.word ?? controller.project.input]
        : [events.first.before, ...events.map((e) => e.after)];
    final last = events.lastOrNull;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Выполнение Маркова',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ExecutionControls(controller: controller, turing: false),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (controller.error != null)
                    Text(controller.error!, style: TextStyle(color: muted)),
                  SelectableText(
                    words.map(shownWord).join(' → '),
                    style: mono.copyWith(fontSize: 16),
                  ),
                  if (run != null)
                    Text(
                      statusLabel(run.status),
                      style: TextStyle(color: muted),
                    ),
                  if (last != null)
                    Text(
                      'Правило ${last.rule}: позиция ${last.position + 1}${last.terminal ? ' · заключительное, выполнение остановлено' : ''}',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  if (run != null && run.steps > events.length)
                    Text(
                      'Показаны последние ${events.length} подстановок',
                      style: TextStyle(color: muted),
                    ),
                  if (run != null &&
                      run.status == ExecutionStatus.halted &&
                      run.detail.isNotEmpty)
                    Text(
                      run.detail,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
