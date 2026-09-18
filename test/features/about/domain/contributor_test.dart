import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/about/domain/entities/contributor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every credited avatar is really declared in the app bundle', () async {
    // Image.asset's errorBuilder would paint a blank circle for a missing
    // asset without failing anything, so the bundle is asked directly.
    for (final contributor in hoopixContributors) {
      final data = await rootBundle.load(contributor.avatarAsset);
      expect(data.lengthInBytes, greaterThan(0), reason: contributor.name);
    }
    final creator = await rootBundle.load('assets/creators/tiavina.png');
    expect(creator.lengthInBytes, greaterThan(0));
  });

  test('every contributor links to a real https GitHub profile', () {
    for (final contributor in hoopixContributors) {
      final url = Uri.parse(contributor.profileUrl);
      expect(url.scheme, 'https', reason: contributor.name);
      expect(url.host, 'github.com', reason: contributor.name);
      expect(url.pathSegments.where((s) => s.isNotEmpty), hasLength(1));
    }
  });

  test('the credited list is not empty', () {
    expect(hoopixContributors, isNotEmpty);
  });
}
