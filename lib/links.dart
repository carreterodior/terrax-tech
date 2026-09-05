/// Public TERRAX URLs used by the app.
///
/// Google Play and Apple both require a working privacy-policy link inside
/// the app (Play User Data policy; App Store guideline 5.1.1). Keep every
/// link here so the paywall, the About sheet and the store listings all
/// point at the same place — a dead link is a review rejection.
class TerraxLinks {
  TerraxLinks._();

  static const website = 'https://terraxgear.com';
  static const privacyPolicy = 'https://terraxgear.com/privacy';
  static const supportEmail = 'support@terraxgear.com';

  static Uri get websiteUri => Uri.parse(website);
  static Uri get privacyPolicyUri => Uri.parse(privacyPolicy);
  static Uri get supportEmailUri => Uri(
        scheme: 'mailto',
        path: supportEmail,
        queryParameters: const {'subject': 'TERRAX TECH app'},
      );
}
