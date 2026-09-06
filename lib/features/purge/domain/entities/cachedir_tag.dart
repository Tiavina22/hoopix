import 'dart:convert';
import 'dart:io';

import 'package:hoopix/features/purge/domain/entities/purge_constants.dart';

/// Ports `mole_dir_has_cachedir_tag` (`lib/clean/purge_shared.sh`): whether
/// [dir] is a cache root by the
/// [Cache Directory Tagging Specification](https://bford.info/cachedir/)
/// convention purge also honors, independent of the named [purgeTargets]
/// list. A symlinked tag file never qualifies — only a real file directly
/// in [dir] whose first bytes are the exact signature counts.
bool hasCachedirTag(String dir) {
  final tagPath = '$dir/CACHEDIR.TAG';
  if (FileSystemEntity.typeSync(tagPath, followLinks: false) !=
      FileSystemEntityType.file) {
    return false;
  }

  final RandomAccessFile handle;
  try {
    handle = File(tagPath).openSync();
  } on FileSystemException {
    return false;
  }

  try {
    final bytes = handle.readSync(cachedirTagSignature.length);
    return const Utf8Decoder(allowMalformed: true).convert(bytes) ==
        cachedirTagSignature;
  } on FileSystemException {
    return false;
  } finally {
    handle.closeSync();
  }
}
