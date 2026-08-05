import 'package:flutter/material.dart';

import '../../ble/device_driver.dart';

/// Offers to protect a device with a PIN once it is plausibly the user's own
/// (see `DeviceSecurity`). Renders generically off [DeviceDriver] — no
/// protocol knowledge here (rule 1).
///
/// Policy (do not weaken): the current PIN is always required and never
/// substituted with a factory default. Vendor apps hardcode `1234`, which
/// would let anyone lock an owner out of their own device.
///
/// Dismissing the dialog (tap outside / back) means "ask again on a later
/// connect"; only the explicit "Don't ask again" button calls [onDeclined].
Future<void> showPinSetupDialog(
  BuildContext context, {
  required DeviceDriver driver,
  required Future<void> Function() onDeclined,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PinSetupDialog(driver: driver, onDeclined: onDeclined),
  );
}

class _PinSetupDialog extends StatefulWidget {
  final DeviceDriver driver;
  final Future<void> Function() onDeclined;
  const _PinSetupDialog({required this.driver, required this.onDeclined});

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _current.text.trim();
    final next = _next.text.trim();
    if (current.isEmpty || next.isEmpty) {
      setState(() => _error = 'Both PINs are required. If you never set one, '
          'use the factory PIN from the device\'s manual.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.driver.changeDevicePin(current: current, next: next);
      if (!mounted) return;
      // Grab the messenger before popping — the dialog's context is gone after.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(
          content: Text('PIN set. Keep it safe — it cannot be recovered '
              'from the device.')));
    } on ArgumentError catch (e) {
      setState(() {
        _busy = false;
        _error = e.message.toString();
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not set the PIN: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Protect this device?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This device accepts commands from any phone in range. Set a '
            'PIN so only you can control it.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _current,
            autofocus: true,
            obscureText: true,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Current PIN',
              helperText: 'Required — check the device\'s manual for the '
                  'factory PIN if you never set one.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _next,
            obscureText: true,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'New PIN'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  await widget.onDeclined();
                  if (context.mounted) Navigator.of(context).pop();
                },
          child: const Text('Don\'t ask again'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Set PIN'),
        ),
      ],
    );
  }
}
