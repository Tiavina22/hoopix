import 'dart:io';

/// Replaces the file at [path] with [lines], creating its directory.
///
/// Written to a sibling file and renamed over the old one, so a reader
/// never sees a half-written file and a failed write leaves the previous
/// one intact.
Future<void> writeLinesAtomically(String path, List<String> lines) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final staging = File('$path.saving');
  await staging.writeAsString('${lines.join('\n')}\n', flush: true);
  await staging.rename(path);
}

/// The file's lines, or null when there is no file or it cannot be read.
List<String>? readLinesSync(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsLinesSync();
  } on Object {
    return null;
  }
}
