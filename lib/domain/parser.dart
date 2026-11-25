import 'markov.dart';

class MarkovParser {
  /// Whitespace separates notation only. It is not a word symbol. Rule symbols
  /// extend the working alphabet; only initial input is restricted to Σ.
  MarkovProgram parse(String source, String inputAlphabet) {
    if (source.length > 100000) {
      throw const FormatException('Исходный текст превышает 100 000 знаков');
    }
    final sigma = symbols(inputAlphabet.replaceAll(RegExp(r'\s'), '')).toSet();
    if (sigma.isEmpty) {
      throw const FormatException('Задайте непустой входной алфавит');
    }
    if (sigma.length > 32) {
      throw const FormatException('Не более 32 входных символов');
    }
    if (sigma.contains('λ'.runes.single) || sigma.contains('σ'.runes.single)) {
      throw const FormatException(
        'λ обозначает пустоту, σ — начало ленты; не включайте их во входной алфавит',
      );
    }
    final alphabet = {...sigma};
    final rules = <Rule>[];
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i]
          .trim()
          .replaceAll('→·', '->.')
          .replaceAll('→.', '->.')
          .replaceAll('→', '->');
      if (line.isEmpty || line.startsWith('//')) continue;
      Never fail(String reason) =>
          throw FormatException('Строка ${i + 1}: $reason');
      final at = line.indexOf('->');
      if (at < 0) fail('не найден оператор подстановки ->');
      if (line.indexOf('->', at + 2) >= 0) {
        fail('в строке должен быть один оператор');
      }
      var lhs = line.substring(0, at).trim();
      var rhs = line.substring(at + 2);
      final terminal = rhs.startsWith('.');
      if (terminal) rhs = rhs.substring(1);
      rhs = rhs.trim();
      if (lhs.contains('.') || rhs.contains('.')) {
        fail('неверный синтаксис терминального правила: используйте ->.');
      }
      if (RegExp(r'\s').hasMatch(lhs + rhs)) {
        fail('пробелы внутри слова не поддерживаются');
      }
      if (lhs.contains('>') ||
          lhs.contains('<') ||
          rhs.contains('>') ||
          rhs.contains('<')) {
        fail('символы < и > зарезервированы синтаксисом');
      }
      // A standalone λ denotes the empty word, never a user tape symbol.
      if (lhs == 'λ') lhs = '';
      if (rhs == 'λ') rhs = '';
      if ((lhs + rhs).contains('λ') || (lhs + rhs).contains('σ')) {
        fail(
          'λ допустима только как пустая часть правила; σ — служебный символ',
        );
      }
      final left = symbols(lhs), right = symbols(rhs);
      if (left.length > 128 || right.length > 128) {
        fail('длина части правила превышает 128 символов');
      }
      alphabet.addAll([...left, ...right]);
      rules.add(Rule(rules.length + 1, i + 1, left, right, terminal));
      if (rules.length > 100) fail('не более 100 правил');
    }
    if (alphabet.length > 64) {
      throw const FormatException('Рабочий алфавит превышает 64 символа');
    }
    return MarkovProgram(source, sigma, alphabet, rules);
  }
}
