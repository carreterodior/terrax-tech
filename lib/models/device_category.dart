/// First-class device categories. Every device has one; the driver assigns a
/// default and the user can recategorize. The home screen groups by category.
enum DeviceCategory {
  lightStrips('Light Strips'),
  bulbs('Bulbs'),
  automotive('Automotive'),
  other('Other');

  final String label;
  const DeviceCategory(this.label);

  static DeviceCategory fromName(String? name) => DeviceCategory.values
      .firstWhere((c) => c.name == name, orElse: () => DeviceCategory.other);
}
