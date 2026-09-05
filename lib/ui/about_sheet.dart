import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../links.dart';

/// About / legal sheet, reachable from the home app bar.
///
/// Its job is the in-app privacy-policy link that Google Play and the App
/// Store require; the rest is the minimum context a user expects next to it.
Future<void> showAboutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const AboutSheet(),
  );
}

class AboutSheet extends StatelessWidget {
  const AboutSheet({super.key});

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TERRAX TECH', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Controls TERRAX Bluetooth accessories directly from your phone. '
              'The app works offline and collects no personal data.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              subtitle: const Text(TerraxLinks.privacyPolicy),
              onTap: () => _open(context, TerraxLinks.privacyPolicyUri),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.language),
              title: const Text('Website'),
              subtitle: const Text(TerraxLinks.website),
              onTap: () => _open(context, TerraxLinks.websiteUri),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mail_outline),
              title: const Text('Support'),
              subtitle: const Text(TerraxLinks.supportEmail),
              onTap: () => _open(context, TerraxLinks.supportEmailUri),
            ),
          ],
        ),
      ),
    );
  }
}
