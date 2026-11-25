import 'dart:convert';
import 'dart:io';

import 'project.dart';

class WorkspaceSnapshot {
  final List<StudioProject> projects;
  final String? selected;
  const WorkspaceSnapshot(this.projects, this.selected);
}

/// Two alternating snapshots preserve the last valid generation after a failed
/// write. Calls are serialized to prevent older autosaves overwriting newer ones.
class ProjectRepository {
  final Directory directory;
  Future<void> _pending = Future.value();
  int _generation = 0;
  ProjectRepository(this.directory);
  Future<WorkspaceSnapshot> load() async {
    await directory.create(recursive: true);
    Map<String, dynamic>? latest;
    var hadFiles = false;
    for (final slot in ['a', 'b']) {
      final file = File('${directory.path}/workspace_$slot.json');
      if (!await file.exists()) continue;
      hadFiles = true;
      try {
        final parsed =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (parsed['version'] != 1 ||
            parsed['generation'] is! int ||
            parsed['projects'] is! List) {
          continue;
        }
        for (final j in parsed['projects'] as List) {
          StudioProject.fromJson(j as Map<String, dynamic>);
        }
        if (latest == null ||
            (parsed['generation'] as int) > (latest['generation'] as int)) {
          latest = parsed;
        }
      } catch (_) {
        /* The other slot can still be valid. */
      }
    }
    if (latest == null) {
      if (hadFiles) {
        throw const FormatException(
          'Оба снимка хранилища повреждены. Файлы сохранены для восстановления.',
        );
      }
      return const WorkspaceSnapshot([], null);
    }
    _generation = latest['generation'] as int;
    return WorkspaceSnapshot([
      for (final j in latest['projects'] as List)
        StudioProject.fromJson(j as Map<String, dynamic>),
    ], latest['selected'] as String?);
  }

  Future<void> save(List<StudioProject> projects, String selected) {
    final payload = jsonEncode({
      'version': 1,
      'projects': projects.map((p) => p.toJson()).toList(),
      'selected': selected,
    });
    final operation = _pending.catchError((Object _) {}).then((_) async {
      await directory.create(recursive: true);
      final generation = _generation + 1;
      final target = File(
        '${directory.path}/workspace_${generation.isEven ? 'a' : 'b'}.json',
      );
      final temporary = File('${target.path}.tmp');
      final data = jsonDecode(payload) as Map<String, dynamic>;
      data['generation'] = generation;
      await temporary.writeAsString(jsonEncode(data), flush: true);
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
      _generation = generation;
    });
    _pending = operation;
    return operation;
  }
}
