import 'package:material_ui/material_ui.dart';

import '../execution/verification.dart';
import 'studio_controller.dart';
import 'theme.dart';

Future<void> showWordCheck(BuildContext context, StudioController controller) =>
    showDialog<void>(
      context: context,
      builder: (context) => _WordCheck(controller: controller),
    );

class _WordCheck extends StatefulWidget {
  final StudioController controller;
  const _WordCheck({required this.controller});
  @override
  State<_WordCheck> createState() => _WordCheckState();
}

class _WordCheckState extends State<_WordCheck> {
  late final input = TextEditingController(
    text: widget.controller.project.input,
  );
  StudioController get c => widget.controller;
  @override
  void dispose() {
    c.cancelVerification(notify: false);
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final result = c.verification.lastOrNull;
      return AlertDialog(
        title: Text('Проверить на слове'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Обе программы получат одно и то же слово. Сравним, что получилось.',
                  style: TextStyle(color: muted, height: 1.5),
                ),
                SizedBox(height: 18),
                TextField(
                  key: Key('check-input'),
                  controller: input,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Входное слово',
                    hintText: 'Оставьте пустым для пустого слова',
                  ),
                  onChanged: (v) => c.edit(input: v),
                ),
                SizedBox(height: 16),
                if (c.error != null)
                  Text(c.error!, style: TextStyle(color: muted)),
                if (c.verifying) LinearProgressIndicator(),
                if (result != null) ...[
                  SelectableText(
                    'Марков: ${shownWord(result.markovWord)}\nТьюринг: ${result.turingWord == null ? 'не завершено' : shownWord(result.turingWord!)}',
                    style: mono.copyWith(fontSize: 14),
                  ),
                  SizedBox(height: 12),
                  Text(
                    switch (result.verdict) {
                      Verdict.match => 'Результаты совпадают',
                      Verdict.mismatch => 'Результаты различаются',
                      Verdict.inconclusive =>
                        'Проверка не завершена: достигнут лимит вычислений',
                    },
                    style: TextStyle(
                      color: result.verdict == Verdict.match ? success : muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Закрыть'),
          ),
          FilledButton(
            onPressed: c.verifying
                ? c.cancelVerification
                : c.error == null
                ? () async {
                    try {
                      await c.verify();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  }
                : null,
            child: Text(c.verifying ? 'Остановить' : 'Сравнить результаты'),
          ),
        ],
      );
    },
  );
}
