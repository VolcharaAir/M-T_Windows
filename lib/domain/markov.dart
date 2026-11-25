/// Strings are sequences of Unicode scalar values, never UTF-16 code units.
List<int> symbols(String text) => text.runes.toList(growable: false);
String wordText(Iterable<int> word) => String.fromCharCodes(word);

class Rule {
  final int id;
  final int line;
  final List<int> left;
  final List<int> right;
  final bool terminal;
  Rule(
    this.id,
    this.line,
    Iterable<int> left,
    Iterable<int> right,
    this.terminal,
  ) : left = List.unmodifiable(left),
      right = List.unmodifiable(right);
}

class MarkovProgram {
  final String source;
  final List<int> inputAlphabet;
  final List<int> alphabet;
  final List<Rule> rules;
  MarkovProgram(
    this.source,
    Iterable<int> inputAlphabet,
    Iterable<int> alphabet,
    Iterable<Rule> rules,
  ) : inputAlphabet = List.unmodifiable(inputAlphabet),
      alphabet = List.unmodifiable(alphabet),
      rules = List.unmodifiable(rules);
  void validateInput(String word) {
    if (symbols(word).any((s) => !inputAlphabet.contains(s))) {
      throw const FormatException(
        'Входное слово содержит символ вне входного алфавита',
      );
    }
  }
}
