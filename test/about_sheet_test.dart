import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/links.dart';
import 'package:terrax/ui/about_sheet.dart';

void main() {
  test('privacy policy link points at the live terraxgear.com page', () {
    // Google Play and the App Store reject dead privacy links; the old
    // paywall pointed at terraxtech.com, which does not resolve.
    expect(TerraxLinks.privacyPolicy, 'https://terraxgear.com/privacy');
    expect(TerraxLinks.privacyPolicyUri.host, 'terraxgear.com');
    expect(TerraxLinks.supportEmailUri.scheme, 'mailto');
    expect(TerraxLinks.supportEmailUri.path, 'support@terraxgear.com');
  });

  testWidgets('About sheet shows the privacy policy link', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AboutSheet()),
    ));
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text(TerraxLinks.privacyPolicy), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text(TerraxLinks.supportEmail), findsOneWidget);
  });
}
