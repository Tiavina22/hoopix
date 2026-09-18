/// One person credited in the About dialog: a circular avatar the dialog
/// renders directly from the app bundle, linking out to their GitHub
/// profile.
class Contributor {
  const Contributor({
    required this.name,
    required this.avatarAsset,
    required this.profileUrl,
  });

  final String name;

  /// Path under `assets/contributors/`, declared as a whole directory in
  /// `pubspec.yaml` — adding a contributor here needs no pubspec edit.
  final String avatarAsset;

  final String profileUrl;
}

/// Everyone credited today. One entry now; append here as more join —
/// nothing else about the dialog needs to change.
const hoopixContributors = [
  Contributor(
    name: 'Tiavina',
    avatarAsset: 'assets/contributors/tiavina.png',
    profileUrl: 'https://github.com/Tiavina22',
  ),
];
