import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'studio_controller.dart';
import 'theme.dart';

Future<void> exportData(
  BuildContext context,
  String name,
  String content,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: 650),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: Icon(Icons.close),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    content,
                    style: mono.copyWith(fontSize: 12),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: content));
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Скопировано')));
                      }
                    },
                    icon: Icon(Icons.copy, size: 16),
                    label: Text('Копировать'),
                  ),
                  if (!Platform.isAndroid && !Platform.isIOS)
                    FilledButton.icon(
                      onPressed: () async {
                        try {
                          final location = await getSaveLocation(
                            suggestedName: name,
                          );
                          if (location == null) return;
                          final file = XFile.fromData(
                            Uint8List.fromList(utf8.encode(content)),
                            name: name,
                            mimeType: 'text/plain',
                          );
                          await file.saveTo(location.path);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Не удалось сохранить: $e'),
                              ),
                            );
                          }
                        }
                      },
                      icon: Icon(Icons.save_alt, size: 17),
                      label: Text('Сохранить файл'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> importData(BuildContext context, StudioController c) async {
  try {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'Проект JSON',
          extensions: ['json'],
          uniformTypeIdentifiers: ['public.json'],
        ),
      ],
    );
    if (file == null) return;
    if (await file.length() > 1000000) {
      throw FormatException('Файл превышает 1 МБ');
    }
    await c.importProject(await file.readAsString());
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось открыть: $e')));
    }
  }
}
