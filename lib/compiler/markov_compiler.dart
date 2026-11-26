import '../domain/markov.dart';
import '../domain/turing.dart';
import 'machine_builder.dart';
import 'machine_optimizer.dart';

/// Compiles once for all words over Σ. The result contains ONLY δ transitions.
/// Tape invariant: σ w λλ…; the end is the first blank, not a delimiter.
class MarkovToTuringCompiler {
  TuringMachine compile(MarkovProgram program) {
    final fast = _singleSymbol(program);
    return MachineOptimizer().optimize(fast ?? compileUniversal(program));
  }

  TuringMachine? _singleSymbol(MarkovProgram program) {
    if (program.rules.length != 1) return null;
    final rule = program.rules.single;
    if (rule.terminal ||
        rule.left.length != 1 ||
        rule.right.length != 1 ||
        rule.left.single == rule.right.single) {
      return null;
    }
    final b = TuringMachineBuilder();
    final start = b.state('Начало', 'Прочитать σ и перейти к первому символу');
    final scan = b.state(
      'Замена символа',
      'Один проход: заменить все ${TapeSymbol.label(rule.left.single)} на ${TapeSymbol.label(rule.right.single)}',
      rule.id,
    );
    final halt = b.state('Завершение', 'Все вхождения заменены');
    b.add(start, TapeSymbol.left, scan, TapeSymbol.left, Direction.right);
    for (final symbol in program.alphabet) {
      b.add(
        scan,
        symbol,
        scan,
        symbol == rule.left.single ? rule.right.single : symbol,
        Direction.right,
      );
    }
    b.add(scan, TapeSymbol.blank, halt, TapeSymbol.blank, Direction.stay);
    return b.build(program.inputAlphabet, program.alphabet, start, {halt});
  }

  /// Reference path, also used to regression-test safe optimizations.
  TuringMachine compileUniversal(MarkovProgram program) {
    final b = TuringMachineBuilder();
    final a = program.alphabet;
    const l = TapeSymbol.left, r = TapeSymbol.blank, blank = TapeSymbol.blank;
    const L = Direction.left, R = Direction.right, S = Direction.stay;
    final anchors = [l, ...a].map(TapeSymbol.anchor).toList();
    final done = b.state('Завершение', 'Нет применимых правил');
    final terminal = b.state(
      'Завершение',
      'Выполнена заключительная подстановка',
    );
    final entries = [
      for (final rule in program.rules)
        b.state('Выбор правила', 'Начало проверки правила ${rule.id}', rule.id),
    ];
    final first = entries.isEmpty ? done : entries.first;
    final start = b.state('Начало', 'Прочитать σ и перейти к первому символу');
    b.add(start, l, first, l, R);

    for (var index = 0; index < program.rules.length; index++) {
      final rule = program.rules[index];
      int state(String phase, String text) => b.state(phase, text, rule.id);
      final rewind = state('Возврат', 'Вернуться к маркеру начала σ');
      for (final s in a) {
        b.add(rewind, s, rewind, s, L);
      }
      b.add(rewind, l, rule.terminal ? terminal : first, l, R);
      // For an equal-length match the search head is already on the last
      // symbol. Rewrite it immediately, then write the remaining cells leftward.
      final overwrite =
          rule.left.isNotEmpty && rule.left.length == rule.right.length;
      var afterMatch = rewind;
      if (overwrite) {
        for (var k = 0; k < rule.left.length - 1; k++) {
          final write = state('Подстановка', 'Перезаписать ячейку ${k + 1}');
          b.add(write, rule.left[k], afterMatch, rule.right[k], L);
          afterMatch = write;
        }
      } else {
        final mark = state(
          'Подстановка',
          'Начать перезапись и отметить опору перед сдвигом',
        );
        final restore = state('Возврат', 'Снять метку опорного символа');
        for (final anchor in anchors) {
          b.add(restore, anchor, rewind, TapeSymbol.unanchor(anchor), S);
        }

        // Each operation starts on the marked predecessor and ends there.
        // Overwrite the shared prefix, then shift only for the length difference.
        final sharedLength = rule.left.length < rule.right.length
            ? rule.left.length
            : rule.right.length;
        var continuation = restore;
        final operations = <(bool, int)>[
          for (var n = sharedLength; n < rule.left.length; n++) (true, 0),
          for (final s in rule.right.skip(sharedLength).toList().reversed)
            (false, s),
        ];
        for (final operation in operations.reversed) {
          final start = state(
            operation.$1 ? 'Удаление' : 'Вставка',
            operation.$1
                ? 'Удалить символ после опоры'
                : 'Вставить ${TapeSymbol.label(operation.$2)} после опоры',
          );
          final home = state('Сдвиг', 'Вернуться к отмеченному символу');
          for (final s in {...a, l, blank}) {
            b.add(home, s, home, s, L);
          }
          for (final anchor in anchors) {
            b.add(home, anchor, continuation, anchor, S);
          }
          final work = state(
            'Сдвиг',
            operation.$1
                ? 'Начало сдвига хвоста влево'
                : 'Начало сдвига хвоста вправо',
          );
          for (final anchor in anchors) {
            b.add(start, anchor, work, anchor, R);
          }
          if (operation.$1) {
            // A blank hole moves right: carry source symbol in finite control,
            // write it one cell left. The first blank ends the shift; no right marker.
            final read = state(
              'Сдвиг влево',
              'Прочитать следующий символ хвоста',
            );
            for (final s in a) {
              b.add(work, s, read, blank, R);
            }
            for (final s in [...a, r]) {
              final write = state(
                'Сдвиг влево',
                'Перенести ${TapeSymbol.label(s)} на одну ячейку влево',
              );
              final advance = state(
                'Сдвиг влево',
                'Пройти освобождённую ячейку',
              );
              b.add(read, s, write, blank, L);
              b.add(write, blank, advance, s, R);
              b.add(
                advance,
                blank,
                s == r ? home : read,
                blank,
                s == r ? L : R,
              );
            }
          } else {
            // Carry one symbol in the state; the first blank receives the final carry.
            final carries = {
              for (final s in a)
                s: state(
                  'Сдвиг вправо',
                  'Перенести ${TapeSymbol.label(s)} вправо',
                ),
            };
            final end = state(
              'Сдвиг вправо',
              'Завершить сдвиг на пустой ячейке',
            );
            void fill(int q, int carried) {
              for (final s in a) {
                b.add(q, s, carries[s]!, carried, R);
              }
              b.add(q, r, end, carried, R);
            }

            fill(work, operation.$2);
            for (final entry in carries.entries) {
              fill(entry.value, entry.key);
            }
            b.add(end, blank, home, r, L);
          }
          continuation = start;
        }
        if (sharedLength == 0) {
          for (final s in [l, ...a]) {
            b.add(mark, s, continuation, TapeSymbol.anchor(s), S);
          }
        } else {
          for (var k = sharedLength - 1; k >= 0; k--) {
            final write = state('Подстановка', 'Перезаписать ячейку ${k + 1}');
            final isAnchor = k == sharedLength - 1;
            b.add(
              write,
              rule.left[k],
              continuation,
              isAnchor ? TapeSymbol.anchor(rule.right[k]) : rule.right[k],
              isAnchor ? S : R,
            );
            continuation = write;
          }
          for (final s in [l, ...a]) {
            b.add(mark, s, continuation, s, R);
          }
        }
        afterMatch = mark;
      }

      // KMP prefix automaton is expanded at COMPILE TIME. At runtime each
      // inspected character is a single δ transition. The first full match
      // encountered has the leftmost starting position (fixed pattern length).
      if (rule.left.isEmpty) {
        for (final s in [...a, r]) {
          b.add(entries[index], s, afterMatch, s, L);
        }
      } else {
        final m = rule.left.length;
        final search = [
          entries[index],
          for (var k = 1; k < m; k++)
            state('Поиск', 'Совпало $k из $m символов образца'),
        ];
        final rewindMatch = [
          for (var k = 0; !overwrite && k < m; k++)
            state('Совпадение', 'Вернуться к опоре: осталось ${m - k} ячеек'),
        ];
        for (var k = 0; k < rewindMatch.length; k++) {
          for (final s in a) {
            b.add(
              rewindMatch[k],
              s,
              k + 1 == m ? afterMatch : rewindMatch[k + 1],
              s,
              L,
            );
          }
        }
        final next = index + 1 < entries.length ? entries[index + 1] : done;
        final failure = state(
          'Выбор правила',
          'Образец не найден; вернуться к началу для следующего правила',
        );
        for (final s in a) {
          b.add(failure, s, failure, s, L);
        }
        b.add(failure, l, next, l, R);
        final prefix = List<int>.filled(m, 0);
        for (var i = 1; i < m; i++) {
          var j = prefix[i - 1];
          while (j > 0 && rule.left[i] != rule.left[j]) {
            j = prefix[j - 1];
          }
          if (rule.left[i] == rule.left[j]) j++;
          prefix[i] = j;
        }
        for (var k = 0; k < m; k++) {
          b.add(search[k], r, failure, r, L);
          for (final s in a) {
            var matched = k;
            while (matched > 0 && rule.left[matched] != s) {
              matched = prefix[matched - 1];
            }
            if (rule.left[matched] == s) matched++;
            if (matched < m) {
              b.add(search[k], s, search[matched], s, R);
            } else if (overwrite) {
              b.add(search[k], s, afterMatch, rule.right.last, L);
            } else {
              b.add(search[k], s, rewindMatch.first, s, S);
            }
          }
        }
      }
    }
    return b.build(program.inputAlphabet, a, start, {done, terminal});
  }
}
