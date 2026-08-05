import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/pro_providers.dart';
import 'theme.dart';

/// TERRAX Pro subscribe screen.
///
/// Apple requires the price, the billing period, auto-renewal wording, a
/// Restore Purchases control, and links to the terms and privacy policy to be
/// visible before purchase (guideline 3.1.2); all of that lives here.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _busy = false;
  String? _error;

  static final _termsUrl = Uri.parse(
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/');
  static final _privacyUrl = Uri.parse('https://terraxtech.com/privacy');

  static const _proFeatures = [
    ('Animation effects', 'Every lighting effect and scene, with speed control'),
    ('Ambient light extras',
        'Welcome lighting, climate reminders, and per zone LED setup'),
    ('Running board setup', 'Learning mode, board light, and safety options'),
  ];

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pro = ref.watch(proServiceProvider);
    final isPro = ref.watch(isProProvider).value ?? false;

    if (isPro) {
      return Scaffold(
        appBar: AppBar(title: const Text('TERRAX Pro')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 56),
                const SizedBox(height: 16),
                Text('Pro is active', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Thanks for supporting TERRAX. Manage or cancel any time in '
                  'Settings > Apple Account > Subscriptions.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('TERRAX Pro')),
      body: TerraxWatermark(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Unlock everything', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Power, color, and brightness are always free for every device '
              'you own. Pro adds the extras:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            for (final (title, detail) in _proFeatures)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          Text(detail, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(_error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
              const SizedBox(height: 12),
            ],
            if (!pro.isAvailable)
              Text(
                'The App Store is not reachable right now, so subscribing is '
                'unavailable. Check your connection and try again.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              FilledButton(
                onPressed: _busy ? null : () => _run(pro.buy),
                child: Text(_busy
                    ? 'Working...'
                    : 'Subscribe ${pro.price ?? ''} per year'.trim()),
              ),
              const SizedBox(height: 8),
              Text(
                'Billed yearly and renews automatically until cancelled. '
                'Cancel any time in Settings > Apple Account > Subscriptions, '
                'at least 24 hours before the period ends.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => _run(pro.restore),
              child: const Text('Restore purchases'),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => launchUrl(_termsUrl,
                      mode: LaunchMode.externalApplication),
                  child: const Text('Terms of use'),
                ),
                TextButton(
                  onPressed: () => launchUrl(_privacyUrl,
                      mode: LaunchMode.externalApplication),
                  child: const Text('Privacy policy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
