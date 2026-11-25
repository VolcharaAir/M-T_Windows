import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markov_turing_studio/main.dart';
import 'package:markov_turing_studio/ui/machine_listing.dart';
import 'package:markov_turing_studio/ui/theme.dart';
import 'package:markov_turing_studio/ui/markov_trace.dart';
import 'package:markov_turing_studio/domain/turing.dart';
import 'package:markov_turing_studio/execution/turing_simulator.dart';
import 'package:markov_turing_studio/execution/limits.dart';
import 'package:markov_turing_studio/ui/studio_controller.dart';
import 'package:markov_turing_studio/storage/project_repository.dart';
import 'package:markov_turing_studio/storage/project.dart';
import 'package:markov_turing_studio/execution/verification.dart';

Future<void> waitFor(StudioController c, bool Function() predicate) async {
  if (predicate()) return;
  final done = Completer<void>();
  void listener() {
    if (predicate() && !done.isCompleted) done.complete();
  }

  c.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 20));
  } finally {
    c.removeListener(listener);
  }
}

class MemoryRepository extends ProjectRepository {
  MemoryRepository() : super(Directory.systemTemp);
  @override
  Future<WorkspaceSnapshot> load() async => const WorkspaceSnapshot([], null);
  @override
  Future<void> save(List<StudioProject> projects, String selected) async {}
}

void main() {
  setUp(() => lightTheme.value = false);
  test('trace contains each real substitution and new notation', () {
    expect(
      traceWord(('01 -> 10', '01', '0011', ExecutionLimits())),
      contains('0011 → 0101 → 1001 → 1010 → 1100'),
    );
    expect(
      transitionText(Transition(2, 48, 3, 49, Direction.right)),
      'S_3 0 -> 1 R S_4',
    );
    expect(
      transitionText(Transition(2, 48, 3, 49, Direction.stay)),
      'S_3 0 -> 1 — S_4',
    );
  });
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final entry in {
      'StudioSans': 'assets/fonts/Roboto-Regular.ttf',
      'StudioMono': 'assets/fonts/DejaVuSansMono.ttf',
    }.entries) {
      final font = FontLoader(entry.key);
      font.addFont(
        Future.value(ByteData.sublistView(File(entry.value).readAsBytesSync())),
      );
      await font.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  Future<StudioController> setupController({bool memory = true}) async {
    final dir = await Directory.systemTemp.createTemp('studio_ui_');
    final c = StudioController(
      memory ? MemoryRepository() : ProjectRepository(dir),
    );
    addTearDown(() {
      c.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    await c.initialize();
    return c;
  }

  testWidgets('desktop UI compiles and steps actual machines', (tester) async {
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = (await tester.runAsync(() => setupController()))!;
    expect(c.error, isNull);
    expect(c.storageError, isNull);
    expect(c.machine, isNotNull);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: StudioApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Алгоритм Маркова'), findsOneWidget);
    expect(find.text('Алгоритм Тьюринга'), findsOneWidget);
    for (final label in [
      'Шаг',
      'Пуск',
      'Учебный',
      'Технический',
      'Контрольная №2',
      'От правил — к машине.',
    ]) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text('М&T'), findsOneWidget);
    expect(find.byKey(Key('input-word')), findsOneWidget);
    await tester.tap(find.byTooltip('Светлая тема'));
    await tester.pumpAndSettle();
    expect(lightTheme.value, true);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Тёмная тема'));
    await tester.pumpAndSettle();
    expect(find.byType(StateLabel), findsWidgets);
    expect(tester.takeException(), isNull);
    final machine = c.machine;
    c.edit(input: '1100');
    await tester.pumpAndSettle();
    expect(
      identical(c.machine, machine),
      true,
      reason: 'input edits must reuse the compiled table',
    );
    c.stepMarkov();
    c.stepTuring();
    await tester.pumpAndSettle();
    expect(c.markov!.steps, 1);
    expect(c.turing!.steps, 1);
    await tester.runAsync(() async {
      await c.verify(batch: true, maxLength: 5);
      await waitFor(c, () => !c.verifying);
    });
    await tester.runAsync(c.save);
    expect(c.error, isNull);
    expect(c.storageError, isNull);
    expect(c.verification.length, 63);
    expect(c.verification.every((r) => r.verdict == Verdict.match), true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pump(Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('1100 → 000'), findsOneWidget);
    if (const bool.fromEnvironment('STUDIO_CAPTURE')) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('test-output').create();
        await File('test-output/desktop.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
  testWidgets(
    'optimized table renders and steps exactly the compiled transitions',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = (await tester.runAsync(() => setupController()))!;
      c.edit(source: '1 -> 0', alphabet: '01', input: '1111');
      await tester.runAsync(c.compile);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('optimized-capture'),
          child: StudioApp(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.machine!.transitions.length, 4);
      expect(find.byType(MachineListing), findsOneWidget);
      expect(find.text('STOP'), findsWidgets);
      expect(c.turing!.head, 0);
      for (var i = 0; i < 6; i++) {
        c.stepTuring();
        await tester.pumpAndSettle();
      }
      expect(c.turing!.steps, 6);
      expect(c.turing!.status, ExecutionStatus.halted);
      expect(WordTapeCodec.decode(c.machine!, c.turing!.tape), '0000');
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('STUDIO_CAPTURE')) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('optimized-capture')),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('test-output').create(recursive: true);
          await File('test-output/optimized.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
  testWidgets('copy exports the full machine, optional check works', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = (await tester.runAsync(() => setupController()))!;
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byTooltip('Копировать всю программу'));
    await tester.pumpAndSettle();
    expect(copied, machineText(c.machine!));
    expect(
      copied!.split('\n').where((s) => s.startsWith('S_')).length,
      c.machine!.transitions.length,
    );
    await tester.tap(find.text('Проверить на слове'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('check-input')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Сравнить результаты'));
      await waitFor(c, () => !c.verifying);
    });
    await tester.pumpAndSettle();
    expect(find.text('Результаты совпадают'), findsOneWidget);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  test('source edits automatically rebuild without execution', () async {
    final c = await setupController();
    final old = c.machine;
    c.edit(source: '0 ->. 1');
    await waitFor(c, () => !c.compiling);
    expect(c.error, isNull);
    expect(identical(c.machine, old), false);
    expect(c.markov!.steps, 0);
    expect(c.turing!.steps, 0);
    c.edit(source: 'bad syntax');
    await waitFor(c, () => !c.compiling);
    expect(c.machine, isNull);
    expect(c.error, contains('Строка 1'));
  });
  test('terminal deletion stops after one substitution, both execution modes agree', () async {
    final c = await setupController();
    c.edit(source: '0 →.', input: '01010');
    await c.compile();
    final machine = c.machine;
    expect(c.error, isNull);
    c.stepMarkov();
    expect(c.markov!.word, '1010');
    expect(c.markov!.status, ExecutionStatus.halted);
    expect(c.markov!.steps, 1);
    c.stepMarkov();
    expect(c.markov!.steps, 1);
    await c.runInstant(false);
    expect(c.error, isNull);
    expect(c.markov!.word, '1010');
    expect(c.markov!.history.length, 1);
    await c.runInstant(true);
    expect(c.error, isNull);
    expect(c.turing!.status, ExecutionStatus.halted);
    expect(WordTapeCodec.decode(c.machine!, c.turing!.tape), '1010');
    expect(identical(c.machine, machine), true);
    c.resetModel(true);
    var safety = 0;
    while (c.turing!.active && safety++ < 5000) {
      c.stepTuring();
    }
    expect(c.turing!.status, ExecutionStatus.halted);
    expect(WordTapeCodec.decode(c.machine!, c.turing!.tape), '1010');
    c.setLimits(const ExecutionLimits(markovSteps: 3, turingSteps: 500));
    c.edit(source: '0 → 0', input: '0');
    await c.compile();
    await c.runInstant(false);
    expect(c.markov!.status, ExecutionStatus.limited);
    expect(c.markov!.steps, 3);
  });
  testWidgets(
    'quick symbols insert at cursor and manual controls advance once',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = (await tester.runAsync(() => setupController()))!;
      c.edit(source: '0 ', input: '01010');
      await tester.runAsync(c.compile);
      await tester.pumpWidget(StudioApp(controller: c));
      await tester.pumpAndSettle();
      final editor = tester
          .widget<TextField>(find.byKey(const Key('markov-editor')))
          .controller!;
      editor.selection = TextSelection.collapsed(offset: editor.text.length);
      await tester.tap(find.byTooltip('Заключительная подстановка'));
      await tester.pump();
      expect(c.project.source, '0 →.');
      await tester.runAsync(c.compile);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Пошагово').first);
      await tester.tap(find.text('Пошагово').first);
      await tester.pumpAndSettle();
      expect(c.markov!.steps, 0);
      await tester.ensureVisible(find.text('Следующая подстановка'));
      await tester.tap(find.text('Следующая подстановка'));
      await tester.pumpAndSettle();
      expect(c.markov!.steps, 1);
      expect(c.markov!.word, '1010');
      expect(find.textContaining('01010 → 1010'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [
    const Size(390, 844),
    const Size(320, 640),
    const Size(844, 390),
    const Size(768, 1024),
  ]) {
    testWidgets('adaptive layout ${size.width} × ${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = (await tester.runAsync(() => setupController()))!;
      await tester.pumpWidget(StudioApp(controller: c));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width < 760) {
        await tester.tap(find.text('Тьюринг').first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Пошагово').last);
        await tester.tap(find.text('Пошагово').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Следующий переход'));
        await tester.tap(find.text('Следующий переход'));
        await tester.pumpAndSettle();
        expect(c.turing!.steps, 1);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Марков').first);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('markov-editor')), findsOneWidget);
      }
    });
  }
  test(
    'cancelled verification stops safely; projects restore and import',
    () async {
      final c = await setupController(memory: false);
      final id = c.project.id;
      c.rename('Проверка');
      await c.save();
      await c.create();
      await c.select(c.projects.firstWhere((p) => p.id == id));
      expect(c.project.name, 'Проверка');
      final text = c.exportProject();
      await c.importProject(text);
      expect(c.projects.length, 3);
      expect(c.project.name, 'Проверка');
      c.edit(source: '0 -> 0');
      await c.compile();
      await c.verify(batch: true, maxLength: 5);
      c.cancelVerification();
      expect(c.verifying, false);
      c.edit(source: 'bad');
      await c.compile();
      expect(c.error, contains('Строка 1'));
      expect(c.machine, isNull);
      await c.deleteCurrent();
      expect(c.projects.length, 2);
    },
  );
}
