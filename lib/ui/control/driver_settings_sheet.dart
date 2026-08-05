import 'package:flutter/material.dart';

import '../../ble/device_driver.dart';

/// Renders a driver's [DriverSetting]s generically — the UI never knows what
/// protocol detail a setting maps to.
void showDriverSettingsSheet(BuildContext context, DeviceDriver driver) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (builderContext, setSheetState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(builderContext).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Device settings',
                    style: Theme.of(builderContext).textTheme.titleLarge),
              ),
              for (final setting in driver.settings)
                switch (setting) {
                  DriverToggleSetting() => SwitchListTile(
                      title: Text(setting.label),
                      subtitle: setting.description != null
                          ? Text(setting.description!)
                          : null,
                      value: setting.value,
                      onChanged: (value) async {
                        await setting.onChanged(value);
                        setSheetState(() {});
                      },
                    ),
                  DriverTextSetting() => ListTile(
                      title: Text(setting.label),
                      subtitle: Text(
                        setting.value.isEmpty
                            ? (setting.description ?? 'Not set')
                            : (setting.obscure ? '••••••' : setting.value),
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () async {
                        final result = await _promptText(
                            builderContext, setting);
                        if (result != null) {
                          await setting.onChanged(result);
                          setSheetState(() {});
                        }
                      },
                    ),
                  DriverButtonSetting() => ListTile(
                      title: Text(setting.label),
                      subtitle: setting.description != null
                          ? Text(setting.description!)
                          : null,
                      trailing: const Icon(Icons.play_arrow_outlined),
                      onTap: () async {
                        try {
                          await setting.run();
                          setSheetState(() {});
                        } catch (e) {
                          if (builderContext.mounted) {
                            ScaffoldMessenger.of(builderContext).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('${setting.label} failed: $e')));
                          }
                        }
                      },
                    ),
                  // Colour and slider controls belong on the control screen,
                  // not in this settings sheet.
                  DriverColorSetting() => const SizedBox.shrink(),
                  DriverSliderSetting() => const SizedBox.shrink(),
                  DriverInfoSetting() => ListTile(
                      title: Text(setting.label),
                      subtitle: Text(setting.value),
                    ),
                  DriverOptionSetting() => ListTile(
                      title: Text(setting.label),
                      subtitle: setting.description != null
                          ? Text(setting.description!)
                          : null,
                      trailing: DropdownButton<Object?>(
                        value: setting.value,
                        hint: const Text('—'),
                        items: [
                          for (final option in setting.options)
                            DropdownMenuItem<Object?>(
                              value: option.value,
                              child: Text(option.label),
                            ),
                        ],
                        onChanged: (value) async {
                          if (value == null) return;
                          // apply(), not onChanged() — see DriverOptionSetting.
                          await setting.apply(value);
                          setSheetState(() {});
                        },
                      ),
                    ),
                },
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<String?> _promptText(
    BuildContext context, DriverTextSetting setting) {
  final controller = TextEditingController(text: setting.value);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(setting.label),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: setting.obscure,
        decoration: InputDecoration(
          labelText: setting.label,
          helperText: setting.description,
          helperMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
