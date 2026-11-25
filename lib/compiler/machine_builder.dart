import '../domain/turing.dart';

class CompilationException implements Exception {
  final String message;
  const CompilationException(this.message);
  @override
  String toString() => message;
}

class TuringMachineBuilder {
  final List<StateInfo> states = [];
  final Map<(int, int), Transition> transitions = {};
  final int maxStates, maxTransitions;
  TuringMachineBuilder({this.maxStates = 40000, this.maxTransitions = 500000});
  int state(String phase, String description, [int? rule]) {
    if (states.length >= maxStates) {
      throw const CompilationException('Превышен лимит состояний компиляции');
    }
    final id = states.length;
    states.add(StateInfo(id, phase, description, rule));
    return id;
  }

  void add(int from, int read, int to, int write, Direction move) {
    if (from < 0 || from >= states.length || to < 0 || to >= states.length) {
      throw StateError('Unknown transition state');
    }
    if (transitions.containsKey((from, read))) {
      throw StateError('Non-deterministic transition: q$from / $read');
    }
    if (transitions.length >= maxTransitions) {
      throw const CompilationException('Превышен лимит переходов компиляции');
    }
    transitions[(from, read)] = Transition(from, read, to, write, move);
  }

  TuringMachine build(
    List<int> sigma,
    List<int> alphabet,
    int initial,
    Set<int> halts,
  ) {
    if (initial < 0 || initial >= states.length) {
      throw StateError('Unknown initial state');
    }
    for (final halt in halts) {
      if (halt < 0 || halt >= states.length) {
        throw StateError('Unknown halt state');
      }
      if (transitions.keys.any((key) => key.$1 == halt)) {
        throw StateError('Halt state has outgoing transitions');
      }
    }
    return TuringMachine(
      inputAlphabet: sigma,
      wordAlphabet: alphabet,
      states: states,
      transitions: transitions,
      initial: initial,
      halts: halts,
    );
  }
}
