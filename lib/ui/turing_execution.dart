import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../execution/limits.dart';
import '../execution/turing_simulator.dart';
import 'execution_controls.dart';
import 'machine_listing.dart';
import 'studio_controller.dart';
import 'theme.dart';

class TuringExecution extends StatefulWidget {
  final StudioController controller;
  const TuringExecution({super.key, required this.controller});
  @override
  State<TuringExecution> createState() => _TuringExecutionState();
}

class _TuringExecutionState extends State<TuringExecution> {
  final scroll = ScrollController();
  bool follow = true;
  int? lastHead;
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, s = c.turing;
    if (s == null) return const SizedBox.shrink();
    if (follow && (lastHead != s.head || lastHead == null)) {
      lastHead = s.head;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.animateTo(
            ((s.head + 20) * 58 - scroll.position.viewportDimension / 2 + 29)
                .clamp(0.0, scroll.position.maxScrollExtent),
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
          );
        }
      });
    }
    String? output;
    if (s.status == ExecutionStatus.halted) {
      try {
        output = WordTapeCodec.decode(s.machine, s.tape);
      } catch (_) {}
    }
    final end = math.max(
      s.head + 20,
      s.tape.cells.keys.fold<int>(0, math.max) + 20,
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Выполнение Тьюринга',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ExecutionControls(controller: c, turing: true),
            const SizedBox(height: 8),
            Row(
              children: [
                StateLabel(
                  s.state,
                  stopLabel: s.machine.halts.contains(s.state)
                      ? s.machine.stateName(s.state)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${statusLabel(s.status)} · ${s.steps} переходов',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: 'Следовать за головкой',
                  onPressed: () => setState(() {
                    follow = !follow;
                    lastHead = null;
                  }),
                  icon: Icon(
                    follow ? Icons.gps_fixed : Icons.gps_not_fixed,
                    size: 18,
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 100,
              child: ListView.builder(
                controller: scroll,
                scrollDirection: Axis.horizontal,
                itemExtent: 58,
                itemCount: end + 21,
                itemBuilder: (context, index) {
                  final position = index - 20, selected = position == s.head;
                  return Column(
                    children: [
                      Text(
                        '$position',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 130),
                        height: 48,
                        width: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? accent : background,
                          border: Border.all(
                            color: selected ? accent : lineColor,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: TapeGlyph(
                          s.tape.read(position),
                          color: selected ? background : accent,
                        ),
                      ),
                      if (selected)
                        Icon(Icons.arrow_drop_up, color: accent, size: 26),
                    ],
                  );
                },
              ),
            ),
            if (output != null)
              SelectableText(
                'Результат: ${shownWord(output)}',
                style: mono.copyWith(fontSize: 15),
              )
            else if (s.status == ExecutionStatus.limited ||
                s.status == ExecutionStatus.error)
              Text(s.detail, style: TextStyle(color: muted, fontSize: 12))
            else
              Text(
                'Выделенная ячейка — положение головки. Подсвечена следующая команда.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}
