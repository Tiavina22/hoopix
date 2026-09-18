import 'dart:convert';
import 'dart:io';

/// One decoded line of `~/Library/Logs/hoopix/operations.log`, exactly as
/// [OperationLog.record] wrote it (`lib/core/platform/operation_log.dart`):
/// `{"at", "command", "outcome", "path", "detail"?, "sizeBytes"?}`.
class RawOperationLogEntry {
  const RawOperationLogEntry({
    required this.at,
    required this.command,
    required this.outcome,
    required this.path,
    this.detail,
    this.sizeBytes,
  });

  final String at;
  final String command;
  final String outcome;
  final String path;
  final String? detail;
  final int? sizeBytes;
}

/// One chunk read backward from the end of the log file.
const _chunkSize = 64 * 1024;

/// Reads the newest entries from hoopix's append-only operation log without
/// loading the whole file: [OperationLog] never rotates or truncates it, so
/// a long-lived install can leave a log far bigger than any one screen needs
/// to show.
///
/// Walks the file backward in fixed-size byte chunks (the same
/// [RandomAccessFile] primitive `hasCachedirTag`
/// (`lib/features/purge/domain/entities/cachedir_tag.dart`) already uses)
/// until it has [limit] lines or reaches the start of the file. Returns
/// newest-first, matching what a history screen shows. A blank line (the
/// file's own trailing newline, or a stray empty one) is never counted
/// toward [limit] — it carries nothing to show. A line that does not parse
/// as the expected JSON shape — a future command's differently-shaped
/// record, a line torn by a crash mid-write — is dropped after counting
/// toward [limit], the same way Mole's own history reader treats an
/// unparseable line as spent budget rather than reason to fail the read.
class OperationLogReader {
  const OperationLogReader();

  Future<List<RawOperationLogEntry>> readRecent(
    String logPath, {
    required int limit,
  }) async {
    if (limit <= 0) return const [];

    final file = File(logPath);
    final RandomAccessFile handle;
    try {
      handle = await file.open();
    } on FileSystemException {
      return const [];
    }

    try {
      final lines = await _readLastLines(handle, limit);
      return lines.map(_parseLine).nonNulls.toList();
    } finally {
      await handle.close();
    }
  }

  /// Reads backward from the end of [handle], returning up to [limit] lines,
  /// newest (closest to the end of the file) first.
  Future<List<String>> _readLastLines(
    RandomAccessFile handle,
    int limit,
  ) async {
    final lines = <String>[];
    // Bytes of the line currently being accumulated, in reverse (last byte
    // of the line first) since the scan walks the file backward.
    var current = <int>[];
    var position = await handle.length();

    while (position > 0 && lines.length < limit) {
      final readSize = position < _chunkSize ? position : _chunkSize;
      position -= readSize;
      await handle.setPosition(position);
      final chunk = await handle.read(readSize);

      for (var i = chunk.length - 1; i >= 0; i--) {
        final byte = chunk[i];
        if (byte != 0x0A) {
          current.add(byte);
          continue;
        }
        // A blank line — including the file's own trailing newline — has
        // nothing to show and never costs a slot of `limit`.
        if (current.isEmpty) continue;
        lines.add(_decodeReversed(current));
        current = [];
        if (lines.length >= limit) break;
      }
    }

    // Whatever is left is the file's very first line, with no newline
    // before it.
    if (lines.length < limit && current.isNotEmpty) {
      lines.add(_decodeReversed(current));
    }

    return lines;
  }

  String _decodeReversed(List<int> reversedBytes) {
    final bytes = reversedBytes.reversed.toList(growable: false);
    return const Utf8Decoder(allowMalformed: true).convert(bytes);
  }

  RawOperationLogEntry? _parseLine(String line) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final at = decoded['at'];
    final command = decoded['command'];
    final outcome = decoded['outcome'];
    final path = decoded['path'];
    if (at is! String ||
        command is! String ||
        outcome is! String ||
        path is! String) {
      return null;
    }
    final detail = decoded['detail'];
    final sizeBytes = decoded['sizeBytes'];
    return RawOperationLogEntry(
      at: at,
      command: command,
      outcome: outcome,
      path: path,
      detail: detail is String ? detail : null,
      sizeBytes: sizeBytes is int ? sizeBytes : null,
    );
  }
}
