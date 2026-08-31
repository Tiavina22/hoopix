/// Whether [path] may be handed to an external command.
///
/// Rejects the shapes that would resolve somewhere other than what the caller
/// read: relative paths, embedded null bytes, and `..` components. Mirrors
/// `validatePath` in Mole's analyzer, which gates its own `open` and delete
/// calls the same way.
///
/// This is an argument check, not a permission check — what may actually be
/// deleted is decided natively, next to the deletion itself.
bool isSafeExternalPath(String path) {
  if (path.isEmpty) return false;
  if (!path.startsWith('/')) return false;
  // Null bytes only. Spaces are ordinary here — "Application Support".
  if (path.codeUnits.contains(0)) return false;
  return !path.split('/').contains('..');
}
