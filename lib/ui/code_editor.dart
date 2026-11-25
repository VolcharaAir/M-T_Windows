import 'package:material_ui/material_ui.dart';

import 'theme.dart';

class MarkovCodeController extends TextEditingController {
  int? _activeLine;
  int? get activeLine => _activeLine;
  set activeLine(int? value) {
    if (_activeLine == value) return;
    _activeLine = value;
    notifyListeners();
  }

  MarkovCodeController({super.text});
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <TextSpan>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final value = lines[i];
      final highlight = activeLine == i + 1
          ? accent.withValues(alpha: .2)
          : Colors.transparent;
      final base = (style ?? mono).copyWith(backgroundColor: highlight);
      final op = RegExp(r'(?:->|→)\.?').firstMatch(value);
      if (value.trimLeft().startsWith('//')) {
        spans.add(
          TextSpan(
            text: value,
            style: base.copyWith(color: muted),
          ),
        );
      } else if (op == null) {
        spans.add(TextSpan(text: value, style: base));
      } else {
        spans.add(
          TextSpan(
            text: value.substring(0, op.start),
            style: base.copyWith(color: cyan),
          ),
        );
        spans.add(
          TextSpan(
            text: op.group(0),
            style: base.copyWith(color: accent, fontWeight: FontWeight.bold),
          ),
        );
        spans.add(
          TextSpan(
            text: value.substring(op.end),
            style: base.copyWith(color: accent),
          ),
        );
      }
      if (i < lines.length - 1) spans.add(TextSpan(text: '\n', style: base));
    }
    return TextSpan(style: style, children: spans);
  }
}

class CodeEditor extends StatefulWidget {
  final String source;
  final int? activeLine;
  final ValueChanged<String> onChanged;
  const CodeEditor({
    super.key,
    required this.source,
    required this.onChanged,
    this.activeLine,
  });
  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  late final controller = MarkovCodeController(text: widget.source);
  @override
  void didUpdateWidget(CodeEditor old) {
    super.didUpdateWidget(old);
    if (controller.text != widget.source) {
      controller.value = TextEditingValue(
        text: widget.source,
        selection: TextSelection.collapsed(offset: widget.source.length),
      );
    }
  }

  @override
  void dispose() {
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  final focus = FocusNode();
  void insert(String text) {
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : start;
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    widget.onChanged(controller.text);
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
        child: Wrap(
          spacing: 4,
          children: [
            for (final pair in [
              ('→', 'Обычная подстановка'),
              ('→.', 'Заключительная подстановка'),
              ('\n', 'Новое правило'),
            ])
              Tooltip(
                message: pair.$2,
                child: TextButton(
                  onPressed: () => insert(pair.$1),
                  child: Text(pair.$1 == '\n' ? '↵' : pair.$1, style: mono),
                ),
              ),
            TextButton(
              onPressed: () => insert(''),
              child: const Text('ε — пусто'),
            ),
          ],
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            key: const Key('markov-editor'),
            controller: controller,
            focusNode: focus,
            onChanged: widget.onChanged,
            style: mono,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: 'Например: 0 →. 1',
            ),
          ),
        ),
      ),
    ],
  );
}
