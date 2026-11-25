enum ExecutionStatus { ready, running, halted, limited, stopped, error }

String statusLabel(ExecutionStatus s) => switch (s) {
  ExecutionStatus.ready => 'Готов к запуску',
  ExecutionStatus.running => 'Выполняется',
  ExecutionStatus.halted => 'Завершён',
  ExecutionStatus.limited => 'Достигнуто ограничение выполнения',
  ExecutionStatus.stopped => 'Остановлен пользователем',
  ExecutionStatus.error => 'Ошибка исполнения',
};

class ExecutionLimits {
  final int markovSteps,
      turingSteps,
      maxWordLength,
      maxCells,
      milliseconds,
      history;
  const ExecutionLimits({
    this.markovSteps = 1000,
    this.turingSteps = 200000,
    this.maxWordLength = 4096,
    this.maxCells = 8192,
    this.milliseconds = 5000,
    this.history = 300,
  });
  Map<String, int> toJson() => {
    'markovSteps': markovSteps,
    'turingSteps': turingSteps,
    'maxWordLength': maxWordLength,
    'maxCells': maxCells,
    'milliseconds': milliseconds,
    'history': history,
  };
  factory ExecutionLimits.fromJson(Map<String, dynamic> j) {
    int read(String k, int fallback, int ceiling) {
      final value = j[k];
      if (value is! int || value < 1 || value > ceiling) return fallback;
      return value;
    }

    return ExecutionLimits(
      markovSteps: read('markovSteps', 1000, 1000000),
      turingSteps: read('turingSteps', 200000, 10000000),
      maxWordLength: read('maxWordLength', 4096, 100000),
      maxCells: read('maxCells', 8192, 200000),
      milliseconds: read('milliseconds', 5000, 120000),
      history: read('history', 300, 10000),
    );
  }
}
