import 'package:material_ui/material_ui.dart';

import '../domain/markov.dart';
import '../domain/turing.dart';
import 'theme.dart';

String displaySymbol(int s) => s >= 0 ? wordText([s]) : TapeSymbol.label(s);
String transitionText(Transition t, {TuringMachine? machine}) =>
    '${machine?.stateName(t.from) ?? 'S_${t.from + 1}'} ${displaySymbol(t.read)} -> ${displaySymbol(t.write)} ${t.move == Direction.stay ? '—' : directionLabel(t.move)} ${machine?.stateName(t.to) ?? 'S_${t.to + 1}'}';
String machineText(TuringMachine machine) => [
  'Старт: ${machine.stateName(machine.initial)}',
  'Остановки: ${machine.halts.map(machine.stateName).join(', ')}',
  'Лента на входе: σ слово λλ…; головка на σ.',
  'λ — пустая ячейка; σ — начало слова; правой границы нет. ⟦…⟧ — временная метка.',
  'R — вправо, L — влево, — — без движения, STOP — остановка.',
  ...machine.transitions.values.map((t) => transitionText(t, machine: machine)),
].join('\n');

class StateLabel extends StatelessWidget {
  final int number;
  final String? stopLabel;
  const StateLabel(this.number, {super.key, this.stopLabel});
  @override
  Widget build(BuildContext context) => stopLabel != null
      ? Text(
          stopLabel!,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
        )
      : Semantics(
          label: 'Состояние S ${number + 1}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'S',
                style: TextStyle(
                  fontFamily: 'StudioSans',
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              Transform.translate(
                offset: const Offset(0, 3),
                child: Text(
                  '${number + 1}',
                  style: TextStyle(
                    fontFamily: 'StudioSans',
                    fontSize: 12,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        );
}

class TapeGlyph extends StatelessWidget {
  final int symbol;
  final Color? color;
  const TapeGlyph(this.symbol, {super.key, this.color});
  @override
  Widget build(BuildContext context) {
    final marked = TapeSymbol.isAnchor(symbol);
    final raw = marked ? TapeSymbol.unanchor(symbol) : symbol;
    final label = TapeSymbol.label(raw);
    final tooltip = marked
        ? 'Отмеченный символ $label: временная опора для сдвига'
        : symbol == TapeSymbol.blank
        ? 'Пустая ячейка ленты'
        : symbol == TapeSymbol.left
        ? 'Маркер начала слова σ'
        : 'Символ «$label»';
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: marked
            ? BoxDecoration(
                border: Border.all(color: color ?? accent),
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'StudioMono',
            fontFamilyFallback: const ['StudioSans'],
            fontSize: 19,
            color: color ?? accent,
          ),
        ),
      ),
    );
  }
}

class MachineListing extends StatefulWidget {
  final TuringMachine machine;
  final int? state, read;
  const MachineListing({
    super.key,
    required this.machine,
    this.state,
    this.read,
  });
  @override
  State<MachineListing> createState() => _MachineListingState();
}

class _MachineListingState extends State<MachineListing> {
  late List<Transition> rows;
  late Map<(int, int), int> indices;
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _rows();
  }

  void _rows() {
    rows = widget.machine.transitions.values.toList()
      ..sort((a, b) {
        final q = a.from.compareTo(b.from);
        if (q != 0) return q;
        if (a.read == TapeSymbol.blank) return 1;
        if (b.read == TapeSymbol.blank) return -1;
        return a.read.compareTo(b.read);
      });
    indices = {
      for (var i = 0; i < rows.length; i++) (rows[i].from, rows[i].read): i,
    };
  }

  @override
  void didUpdateWidget(MachineListing old) {
    super.didUpdateWidget(old);
    if (old.machine != widget.machine) _rows();
    if (old.state != widget.state || old.read != widget.read) {
      final index = indices[(widget.state, widget.read)];
      if (index != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroll.hasClients) {
            scroll.animateTo(
              (index * 48 - scroll.position.viewportDimension / 2).clamp(
                0.0,
                scroll.position.maxScrollExtent,
              ),
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Widget cell(Widget child, int flex) => Expanded(
    flex: flex,
    child: Center(child: child),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Старт:'),
            StateLabel(widget.machine.initial),
            const SizedBox(width: 8),
            const Text('Остановка:'),
            for (final q in widget.machine.halts)
              StateLabel(q, stopLabel: widget.machine.stateName(q)),
          ],
        ),
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: box.maxWidth < 480 ? 480 : box.maxWidth,
              child: Column(
                children: [
                  Container(
                    height: 34,
                    color: background,
                    child: Row(
                      children: [
                        for (final text in [
                          'Состояние',
                          'Читает',
                          '→',
                          'Пишет',
                          'Ход',
                          'Далее',
                        ])
                          cell(
                            Text(
                              text,
                              style: TextStyle(
                                color: muted,
                                fontSize: 11,
                                fontFamily: 'StudioMono',
                              ),
                            ),
                            text == '→' ? 1 : 2,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      itemExtent: 48,
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final t = rows[index],
                            selected =
                                t.from == widget.state && t.read == widget.read;
                        return Tooltip(
                          message:
                              '${widget.machine.states[t.from].description}\n${transitionText(t, machine: widget.machine)}',
                          child: Container(
                            key: ValueKey('transition-${t.from}-${t.read}'),
                            decoration: BoxDecoration(
                              color: selected
                                  ? lineColor
                                  : index.isEven
                                  ? surface
                                  : background,
                              border: Border(
                                left: BorderSide(
                                  color: selected ? accent : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                cell(StateLabel(t.from), 2),
                                cell(TapeGlyph(t.read), 2),
                                cell(
                                  const Text(
                                    '→',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontFamily: 'StudioMono',
                                    ),
                                  ),
                                  1,
                                ),
                                cell(TapeGlyph(t.write), 2),
                                cell(
                                  Text(
                                    t.move == Direction.stay
                                        ? '—'
                                        : directionLabel(t.move),
                                    style: mono.copyWith(fontSize: 18),
                                  ),
                                  2,
                                ),
                                cell(
                                  StateLabel(
                                    t.to,
                                    stopLabel:
                                        widget.machine.halts.contains(t.to)
                                        ? widget.machine.stateName(t.to)
                                        : null,
                                  ),
                                  2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
