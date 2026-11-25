import '../execution/limits.dart';

class StudioProject {
  final String id;
  String name, alphabet, source, input;
  ExecutionLimits limits;
  final DateTime createdAt;
  DateTime updatedAt;
  StudioProject({
    required this.id,
    required this.name,
    required this.alphabet,
    required this.source,
    required this.input,
    required this.createdAt,
    required this.updatedAt,
    this.limits = const ExecutionLimits(),
  });
  factory StudioProject.fresh(int n) {
    final now = DateTime.now();
    return StudioProject(
      id: '${now.microsecondsSinceEpoch}',
      name: 'Исследование $n',
      alphabet: '01',
      source: '01 -> 10\n11 ->. 0',
      input: '0101',
      createdAt: now,
      updatedAt: now,
    );
  }
  Map<String, dynamic> toJson() => {
    'format': 'markov-turing-project',
    'version': 1,
    'id': id,
    'name': name,
    'alphabet': alphabet,
    'source': source,
    'input': input,
    'limits': limits.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory StudioProject.fromJson(Map<String, dynamic> j) {
    if (j['format'] != 'markov-turing-project' || j['version'] != 1) {
      throw const FormatException('Неподдерживаемый формат проекта');
    }
    String field(String key, int maxLength) {
      final value = j[key];
      if (value is! String || value.length > maxLength) {
        throw FormatException('Неверное поле $key');
      }
      return value;
    }

    final name = field('name', 200);
    if (name.trim().isEmpty) throw const FormatException('Пустое имя проекта');
    return StudioProject(
      id: field('id', 100),
      name: name,
      alphabet: field('alphabet', 200),
      source: field('source', 100000),
      input: field('input', 100000),
      createdAt: DateTime.parse(field('createdAt', 100)),
      updatedAt: DateTime.parse(field('updatedAt', 100)),
      limits: ExecutionLimits.fromJson(
        j['limits'] is Map<String, dynamic>
            ? j['limits'] as Map<String, dynamic>
            : {},
      ),
    );
  }
}
