import 'package:material_ui/material_ui.dart';

import 'studio_controller.dart';
import 'theme.dart';

class ExecutionControls extends StatefulWidget {
  final StudioController controller;
  final bool turing;
  const ExecutionControls({
    super.key,
    required this.controller,
    required this.turing,
  });
  @override
  State<ExecutionControls> createState() => _ExecutionControlsState();
}

class _ExecutionControlsState extends State<ExecutionControls> {
  bool manual = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final busy = widget.turing ? c.turingBusy : c.markovBusy;
    final active = widget.turing
        ? c.turing?.active == true
        : c.markov?.active == true;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.tonal(
          onPressed: busy || c.error != null || c.machine == null
              ? null
              : () {
                  setState(() => manual = false);
                  c.runInstant(widget.turing);
                },
          child: const Text('Выполнить сразу'),
        ),
        OutlinedButton(
          onPressed: busy || c.error != null || c.machine == null
              ? null
              : () {
                  setState(() => manual = true);
                  c.resetModel(widget.turing);
                },
          child: const Text('Пошагово'),
        ),
        if (manual)
          FilledButton(
            onPressed: busy || !active
                ? null
                : widget.turing
                ? c.stepTuring
                : c.stepMarkov,
            child: Text(
              widget.turing ? 'Следующий переход' : 'Следующая подстановка',
            ),
          ),
        IconButton(
          tooltip: 'Начать заново',
          onPressed: () => c.resetModel(widget.turing),
          icon: Icon(Icons.restart_alt, color: muted),
        ),
        if (busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }
}
