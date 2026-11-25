import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../compiler/markov_compiler.dart';
import '../domain/examples.dart';
import '../domain/markov.dart';
import '../domain/parser.dart';
import '../domain/turing.dart';
import '../execution/limits.dart';
import '../execution/markov_interpreter.dart';
import '../execution/turing_simulator.dart';
import '../execution/verification.dart';
import '../storage/project.dart';
import '../storage/project_repository.dart';

(MarkovProgram, TuringMachine) compileSource((String, String) request) {
  final program = MarkovParser().parse(request.$1, request.$2);
  return (program, MarkovToTuringCompiler().compile(program));
}

MarkovInterpreter executeMarkov(
  (MarkovProgram, String, ExecutionLimits) request,
) => MarkovInterpreter(request.$1, request.$2, limits: request.$3)..run();
TuringMachineSimulator executeTuring(
  (TuringMachine, String, ExecutionLimits) request,
) => TuringMachineSimulator(
  request.$1,
  WordTapeCodec.encode(request.$1, request.$2),
  head: 0,
  limits: request.$3,
)..run();

class StudioController extends ChangeNotifier {
  final ProjectRepository repository;
  List<StudioProject> projects = [];
  StudioProject? _project;
  StudioProject get project => _project!;
  MarkovProgram? program;
  TuringMachine? machine;
  MarkovInterpreter? markov;
  TuringMachineSimulator? turing;
  String? error, storageError;
  bool loading = true, compiling = false, verifying = false, saved = true;
  bool markovPlaying = false, turingPlaying = false;
  int batchProgress = 0, batchTotal = 0, speed = 10, markovSpeed = 5;
  int _markovElapsed = 0;
  int _markovRun = 0, _turingRun = 0;
  bool markovBusy = false, turingBusy = false;
  List<VerificationResult> verification = [];
  Timer? _debounce, _saveTimer, _runner;
  int _revision = 0, _verificationRevision = 0;
  Isolate? _verificationIsolate;
  ReceivePort? _verificationPort;
  bool _disposed = false;
  StudioController(this.repository);
  Future<void> initialize() async {
    try {
      final snapshot = await repository.load();
      projects = List.of(snapshot.projects);
      if (projects.isEmpty) projects.add(StudioProject.fresh(1));
      _project =
          projects.where((p) => p.id == snapshot.selected).firstOrNull ??
          projects.first;
    } catch (e) {
      storageError = '$e';
      projects = [StudioProject.fresh(1)];
      _project = projects.first;
    }
    loading = false;
    _runner = Timer.periodic(Duration(milliseconds: 50), (_) => _tick());
    await compile();
    notifyListeners();
  }

  void edit({String? source, String? alphabet, String? input}) {
    if (source != null) project.source = source;
    if (alphabet != null) project.alphabet = alphabet;
    if (input != null) project.input = input;
    _touch();
    reset();
    if (source != null || alphabet != null) {
      _revision++;
      program = null;
      machine = null;
      error = null;
      compiling = true;
      _debounce?.cancel();
      _debounce = Timer(Duration(milliseconds: 400), compile);
    } else {
      _makeRunners();
    }
    notifyListeners();
  }

  void _touch() {
    saved = false;
    project.updatedAt = DateTime.now();
    _saveTimer?.cancel();
    _saveTimer = Timer(Duration(milliseconds: 500), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    final timestamp = project.updatedAt, id = project.id;
    try {
      await repository.save(projects, project.id);
      if (_disposed) return;
      saved = project.id == id && project.updatedAt == timestamp;
      storageError = null;
    } catch (e) {
      if (!_disposed) storageError = '$e';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> compile() async {
    _debounce?.cancel();
    final rev = ++_revision;
    final request = (project.source, project.alphabet);
    compiling = true;
    error = null;
    program = null;
    machine = null;
    reset();
    notifyListeners();
    try {
      final result = await compute(compileSource, request);
      if (_disposed || rev != _revision) return;
      program = result.$1;
      machine = result.$2;
      _makeRunners();
    } catch (e) {
      if (!_disposed && rev == _revision) error = e.toString();
    }
    if (!_disposed && rev == _revision) {
      compiling = false;
      notifyListeners();
    }
  }

  void _makeRunners() {
    if (program == null || machine == null) return;
    try {
      program!.validateInput(project.input);
      markov = MarkovInterpreter(
        program!,
        project.input,
        limits: project.limits,
      );
      turing = TuringMachineSimulator(
        machine!,
        WordTapeCodec.encode(machine!, project.input),
        head: 0,
        limits: project.limits,
      );
      error = null;
    } catch (e) {
      error = e.toString();
      markov = null;
      turing = null;
    }
  }

  void reset() {
    _markovRun++;
    _turingRun++;
    markovBusy = false;
    turingBusy = false;
    markovPlaying = false;
    turingPlaying = false;
    markov = null;
    turing = null;
    cancelVerification(notify: false);
    verification = [];
  }

  void resetExecution() {
    reset();
    _makeRunners();
    notifyListeners();
  }

  void resetModel(bool isTuring) {
    if (program == null || machine == null) return;
    try {
      if (isTuring) {
        _turingRun++;
        turingBusy = false;
        turingPlaying = false;
        turing = TuringMachineSimulator(
          machine!,
          WordTapeCodec.encode(machine!, project.input),
          head: 0,
          limits: project.limits,
        );
      } else {
        _markovRun++;
        markovBusy = false;
        markovPlaying = false;
        markov = MarkovInterpreter(
          program!,
          project.input,
          limits: project.limits,
        );
      }
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  Future<void> runInstant(bool isTuring) async {
    if (program == null || machine == null || error != null) return;
    final rev = isTuring ? ++_turingRun : ++_markovRun;
    if (isTuring) {
      turingBusy = true;
      turingPlaying = false;
    } else {
      markovBusy = true;
      markovPlaying = false;
    }
    notifyListeners();
    try {
      if (isTuring) {
        final result = await compute(executeTuring, (
          machine!,
          project.input,
          project.limits,
        ));
        if (!_disposed && rev == _turingRun) turing = result;
      } else {
        final result = await compute(executeMarkov, (
          program!,
          project.input,
          project.limits,
        ));
        if (!_disposed && rev == _markovRun) markov = result;
      }
    } catch (e) {
      if (!_disposed && rev == (isTuring ? _turingRun : _markovRun)) {
        error = '$e';
      }
    }
    if (!_disposed && rev == (isTuring ? _turingRun : _markovRun)) {
      if (isTuring) {
        turingBusy = false;
      } else {
        markovBusy = false;
      }
      notifyListeners();
    }
  }

  void stepMarkov() {
    markovPlaying = false;
    markov?.step();
    markov?.pause();
    notifyListeners();
  }

  void stepTuring() {
    turingPlaying = false;
    turing?.step();
    turing?.pause();
    notifyListeners();
  }

  void playMarkov() {
    if (markov?.active != true) return;
    markovPlaying = !markovPlaying;
    markov?.pause();
    notifyListeners();
  }

  void playTuring() {
    if (turing?.active != true) return;
    turingPlaying = !turingPlaying;
    turing?.pause();
    notifyListeners();
  }

  void stopAll() {
    markov?.stop();
    turing?.stop();
    markovPlaying = false;
    turingPlaying = false;
    notifyListeners();
  }

  void _tick() {
    if (!markovPlaying && !turingPlaying) return;
    final slice = Stopwatch()..start();
    if (markovPlaying) {
      _markovElapsed += 50;
      if (_markovElapsed >= 1000 / markovSpeed) {
        _markovElapsed = 0;
        markov?.step();
        markov?.pause();
        if (markov?.active != true) markovPlaying = false;
      }
    }
    if (turingPlaying) {
      for (var i = 0; i < speed && slice.elapsedMilliseconds < 8; i++) {
        turing?.step();
        if (turing?.active != true) {
          turingPlaying = false;
          break;
        }
      }
      turing?.pause();
    }
    notifyListeners();
  }

  Future<void> select(StudioProject p) async {
    _debounce?.cancel();
    _saveTimer?.cancel();
    reset();
    _project = p;
    _touch();
    await compile();
  }

  Future<void> create() async {
    final p = StudioProject.fresh(projects.length + 1);
    projects.add(p);
    await select(p);
  }

  void rename(String name) {
    if (name.trim().isEmpty) return;
    project.name = name.trim();
    _touch();
    notifyListeners();
  }

  Future<void> deleteCurrent() async {
    projects.removeWhere((p) => p.id == project.id);
    if (projects.isEmpty) projects.add(StudioProject.fresh(1));
    await select(projects.first);
    await save();
  }

  void loadExample(StudyExample example) {
    project.name = example.name;
    edit(
      source: example.source,
      alphabet: example.alphabet,
      input: example.input,
    );
  }

  Future<void> importProject(String text) async {
    if (text.length > 1000000) {
      throw FormatException('Файл проекта превышает 1 МБ');
    }
    final parsed = StudioProject.fromJson(
      jsonDecode(text) as Map<String, dynamic>,
    );
    final now = DateTime.now();
    final p = StudioProject(
      id: '${now.microsecondsSinceEpoch}',
      name: parsed.name,
      alphabet: parsed.alphabet,
      source: parsed.source,
      input: parsed.input,
      createdAt: parsed.createdAt,
      updatedAt: now,
      limits: parsed.limits,
    );
    projects.add(p);
    await select(p);
  }

  void setLimits(ExecutionLimits limits) {
    project.limits = limits;
    _touch();
    resetExecution();
  }

  String exportProject() =>
      JsonEncoder.withIndent('  ').convert(project.toJson());
  String exportMachine() =>
      JsonEncoder.withIndent('  ').convert(machine!.toJson());
  void cancelVerification({bool notify = true}) {
    _verificationRevision++;
    _verificationIsolate?.kill(priority: Isolate.immediate);
    _verificationIsolate = null;
    _verificationPort?.close();
    _verificationPort = null;
    verifying = false;
    if (notify) notifyListeners();
  }

  Future<void> verify({bool batch = false, int maxLength = 5}) async {
    if (program == null || machine == null || error != null) return;
    cancelVerification(notify: false);
    final revision = _verificationRevision;
    final p = program!, m = machine!, limits = project.limits;
    final inputs = batch
        ? EquivalenceVerifier().words(p.inputAlphabet, maxLength).toList()
        : [project.input];
    verification = [];
    batchProgress = 0;
    batchTotal = inputs.length;
    verifying = true;
    notifyListeners();
    final port = ReceivePort();
    _verificationPort = port;
    port.listen((dynamic message) {
      if (_disposed || revision != _verificationRevision) return;
      if (message is VerificationResult) {
        verification.add(message);
        batchProgress++;
        notifyListeners();
      } else if (message == 'done') {
        cancelVerification();
      } else if (message is String) {
        error = message;
        cancelVerification();
      }
    });
    final worker = await Isolate.spawn(verificationWorker, (
      port.sendPort,
      p,
      m,
      inputs,
      limits,
    ));
    if (_disposed || revision != _verificationRevision) {
      worker.kill(priority: Isolate.immediate);
    } else {
      _verificationIsolate = worker;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _saveTimer?.cancel();
    _runner?.cancel();
    cancelVerification(notify: false);
    super.dispose();
  }
}

/// Top-level isolate entry keeps UI controllers, ports and timers out of messages.
void verificationWorker(
  (SendPort, MarkovProgram, TuringMachine, List<String>, ExecutionLimits)
  request,
) {
  final (out, program, machine, inputs, limits) = request;
  try {
    final verifier = EquivalenceVerifier();
    for (final input in inputs) {
      out.send(verifier.verify(program, machine, input, limits: limits));
    }
    out.send('done');
  } catch (e) {
    out.send(e.toString());
  }
}
