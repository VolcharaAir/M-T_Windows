import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../domain/examples.dart';
import 'code_editor.dart';
import 'machine_listing.dart';
import 'studio_controller.dart';
import 'studio_dialogs.dart';
import 'theme.dart';
import 'word_check.dart';
import 'markov_trace.dart';
import 'turing_execution.dart';

/// The primary task is source -> machine. Execution is optional, in a dialog.
class StudioScreen extends StatefulWidget {
  final StudioController controller;
  const StudioScreen({super.key, required this.controller});
  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen>
    with WidgetsBindingObserver {
  StudioController get c => widget.controller;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !c.loading) c.save();
  }

  Future<void> _help() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Как пользоваться'),
      content: SingleChildScrollView(
        child: Text(
          '1. Напишите правила Маркова слева. Например: 0 ->. 1\n\n'
          '2. Справа автоматически появится программа машины Тьюринга. Нажимать «Пуск» для преобразования не нужно.\n\n'
          '3. «Копировать» копирует всю полученную программу. В меню можно сохранить её в файл.\n\n'
          '«Проверить на слове» — необязательная проверка: обе программы вычислят результат для одного входа.\n\n'
          'Запись S_i a -> b R S_j: S_i — текущее состояние, a — прочитанный символ, b — запись, R — вправо (L — влево, — — без движения), S_j — следующее состояние. Остановка задаётся состояниями остановки.\n\n'
          'Одна подстановка Маркова превращается в несколько состояний и переходов: машине нужно найти подстроку и сдвинуть символы. Поэтому справа строк обычно больше.\n\n'
          '-> — обычное правило; ->. — заменить и остановиться. Пустая правая часть удаляет, пустая левая вставляет в начало. Входной алфавит задайте под редактором. Правила могут вводить дополнительные символы.',
          style: TextStyle(height: 1.6),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Понятно')),
      ],
    ),
  );
  Future<void> _symbols() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Обозначения'),
      content: const SingleChildScrollView(
        child: Text(
          'Входной алфавит (например {0, 1}) задаётся под редактором Маркова.\n\nλ — пустая ячейка ленты, а не символ исходного слова.\n\nσ — единственный маркер начала слова. Правой границы нет: за словом идут пустые ячейки λ.\n\nСимвол в рамке (в текстовом экспорте ⟦0⟧, ⟦1⟧, ⟦σ⟧) — временная метка. Она помогает машине сдвигать хвост при удалении или вставке и снимается до завершения.\n\nR — вправо, L — влево, — — без сдвига. Остановка определяется конечным состоянием.\n\n0 →. означает: удалить самый левый ноль и сразу завершить алгоритм. Для 01010 получится 1010, а не 11.\n\nСправа весь текст машины; выделенная строка — следующая команда. Выполнение видно на ленте ниже.',
          style: TextStyle(height: 1.6),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Понятно'),
        ),
      ],
    ),
  );
  Future<void> _projects() => showDialog<void>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Сохранённые алгоритмы'),
      children: [
        for (final p in c.projects)
          SimpleDialogOption(
            onPressed: () {
              c.select(p);
              Navigator.pop(ctx);
            },
            child: Text(p.name),
          ),
      ],
    ),
  );
  void _action(String action) {
    switch (action) {
      case 'new':
        c.create();
      case 'open':
        importData(context, c);
      case 'projects':
        _projects();
      case 'save':
        exportData(context, 'MT-project.json', c.exportProject());
      case 'text':
        if (c.machine != null) {
          exportData(context, 'MT-turing.txt', machineText(c.machine!));
        }
      case 'json':
        if (c.machine != null) {
          exportData(context, 'MT-turing.json', c.exportMachine());
        }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (c.loading) {
        return Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 740;
          return Scaffold(
            appBar: AppBar(
              backgroundColor: background,
              title: Text(
                'М&T',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              actions: [
                IconButton(
                  tooltip: lightTheme.value ? 'Тёмная тема' : 'Светлая тема',
                  onPressed: () => lightTheme.value = !lightTheme.value,
                  icon: Icon(
                    lightTheme.value
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                  ),
                ),

                if (!narrow)
                  TextButton.icon(
                    onPressed: c.machine != null
                        ? () => showWordCheck(context, c)
                        : null,
                    icon: Icon(Icons.check_circle_outline, size: 17),
                    label: Text('Проверить на слове'),
                  )
                else
                  IconButton(
                    tooltip: 'Проверить на слове',
                    onPressed: c.machine != null
                        ? () => showWordCheck(context, c)
                        : null,
                    icon: Icon(Icons.check_circle_outline),
                  ),
                PopupMenuButton<StudyExample>(
                  tooltip: 'Вставить пример',
                  icon: Icon(Icons.code),
                  itemBuilder: (ctx) => [
                    for (final e in examples)
                      PopupMenuItem(value: e, child: Text(e.name)),
                  ],
                  onSelected: c.loadExample,
                ),
                IconButton(
                  tooltip: 'Как пользоваться',
                  onPressed: _help,
                  icon: Icon(Icons.help_outline, size: 21),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Файлы',
                  onSelected: _action,
                  itemBuilder: (ctx) => [
                    PopupMenuItem(value: 'new', child: Text('Новый алгоритм')),
                    PopupMenuItem(
                      value: 'open',
                      child: Text('Открыть файл проекта'),
                    ),
                    PopupMenuItem(
                      value: 'projects',
                      child: Text('Сохранённые алгоритмы'),
                    ),
                    PopupMenuItem(
                      value: 'save',
                      child: Text('Сохранить проект в файл'),
                    ),
                    PopupMenuItem(
                      value: 'text',
                      enabled: c.machine != null,
                      child: Text('Сохранить программу Тьюринга'),
                    ),
                    PopupMenuItem(
                      value: 'json',
                      enabled: c.machine != null,
                      child: Text('Экспорт машины в JSON'),
                    ),
                  ],
                ),
                SizedBox(width: 8),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    if (c.storageError != null)
                      Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Ошибка сохранения: ${c.storageError}',
                          style: TextStyle(color: muted),
                        ),
                      ),
                    if (narrow)
                      Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<int>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(value: 0, label: Text('Марков')),
                              ButtonSegment(value: 1, label: Text('Тьюринг')),
                            ],
                            selected: {tab},
                            onSelectionChanged: (v) =>
                                setState(() => tab = v.first),
                          ),
                        ),
                      ),
                    Expanded(
                      child: narrow
                          ? IndexedStack(
                              index: tab,
                              children: [_source(), _output()],
                            )
                          : Row(
                              children: [
                                Expanded(child: _source()),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: Icon(
                                    Icons.arrow_forward,
                                    size: 20,
                                    color: muted,
                                  ),
                                ),
                                Expanded(child: _output()),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
  Widget _card({
    required Widget title,
    required Widget child,
    Widget? bottom,
  }) => Material(
    color: surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: lineColor),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: title,
        ),
        Divider(height: 1),
        Expanded(child: child),
        if (bottom != null) bottom,
      ],
    ),
  );
  Widget _source() => _card(
    title: Text(
      'Алгоритм Маркова',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    child: LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(
              height: box.maxHeight > 540 ? box.maxHeight - 330 : 200,
              child: CodeEditor(
                key: ValueKey('code-${c.project.id}'),
                source: c.project.source,
                onChanged: (value) => c.edit(source: value),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: _InputWord(
                key: ValueKey('word-${c.project.id}'),
                value: c.project.input,
                onChanged: (value) => c.edit(input: value),
              ),
            ),
            SizedBox(height: 8),
            SizedBox(height: 240, child: MarkovTrace(controller: c)),
          ],
        ),
      ),
    ),
    bottom: Padding(
      padding: EdgeInsets.all(12),
      child: Row(
        children: [
          Tooltip(
            message: 'Допустимые символы входного слова',
            child: Text(
              'Алфавит',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _Alphabet(
              key: ValueKey('alphabet-${c.project.id}'),
              value: c.project.alphabet,
              onChanged: (v) => c.edit(alphabet: v),
            ),
          ),
          SizedBox(width: 10),
          Tooltip(
            message: c.saved
                ? 'Изменения сохранены на устройстве'
                : 'Сохранение…',
            child: Icon(
              c.saved ? Icons.check : Icons.more_horiz,
              size: 16,
              color: muted,
            ),
          ),
        ],
      ),
    ),
  );
  Widget _output() => _card(
    title: Row(
      children: [
        Expanded(
          child: Text(
            'Алгоритм Тьюринга',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Копировать всю программу',
          onPressed: c.machine == null
              ? null
              : () async {
                  await Clipboard.setData(
                    ClipboardData(text: machineText(c.machine!)),
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Программа Тьюринга скопирована')),
                    );
                  }
                },
          icon: Icon(Icons.copy, size: 18),
        ),
      ],
    ),
    child: c.compiling
        ? Center(
            child: Text('Преобразование…', style: TextStyle(color: muted)),
          )
        : c.machine == null
        ? Padding(
            padding: EdgeInsets.all(16),
            child: SelectableText(
              c.error ?? 'Напишите правила слева.',
              style: TextStyle(color: muted, height: 1.6),
            ),
          )
        : LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    height: box.maxHeight > 640 ? box.maxHeight - 340 : 300,
                    child: MachineListing(
                      machine: c.machine!,
                      state: c.turing?.state,
                      read: c.turing?.tape.read(c.turing!.head),
                    ),
                  ),
                  SizedBox(height: 310, child: TuringExecution(controller: c)),
                  TextButton(
                    onPressed: _symbols,
                    child: const Text('Обозначения: σ, λ и метки'),
                  ),
                ],
              ),
            ),
          ),
  );
}

class _Alphabet extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _Alphabet({super.key, required this.value, required this.onChanged});
  @override
  State<_Alphabet> createState() => _AlphabetState();
}

class _AlphabetState extends State<_Alphabet> {
  late final TextEditingController controller = TextEditingController(
    text: widget.value,
  );
  @override
  void didUpdateWidget(_Alphabet old) {
    super.didUpdateWidget(old);
    if (widget.value != controller.text) controller.text = widget.value;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: widget.onChanged,
    style: mono.copyWith(fontSize: 13),
    decoration: InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    autocorrect: false,
  );
}

class _InputWord extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _InputWord({super.key, required this.value, required this.onChanged});
  @override
  State<_InputWord> createState() => _InputWordState();
}

class _InputWordState extends State<_InputWord> {
  late final controller = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(_InputWord old) {
    super.didUpdateWidget(old);
    if (controller.text != widget.value) controller.text = widget.value;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: Key('input-word'),
    controller: controller,
    onChanged: widget.onChanged,
    style: mono,
    decoration: InputDecoration(
      labelText: 'Входное слово',
      hintText: 'Пустое поле — пустое слово',
    ),
    autocorrect: false,
  );
}
