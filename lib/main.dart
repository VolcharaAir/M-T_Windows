import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'storage/project_repository.dart';
import 'ui/studio_controller.dart';
import 'ui/studio_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final directory = await getApplicationSupportDirectory();
    final controller = StudioController(
      ProjectRepository(Directory('${directory.path}/studio')),
    );
    runApp(StudioApp(controller: controller));
    await controller.initialize();
  } catch (e) {
    runApp(
      MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                'Не удалось открыть локальное хранилище.\n$e',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StudioApp extends StatelessWidget {
  final StudioController controller;
  const StudioApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: lightTheme,
    builder: (context, light, _) => MaterialApp(
      title: 'М&T',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: studioTheme(),
      home: StudioScreen(controller: controller),
    ),
  );
}
