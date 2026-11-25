/// First-class device categories. Every device has one; the driver assigns a
/// default and the user can recategorize. The home screen groups by category.
enum DeviceCategory {
  lightStrips('LED strips & mood lights'),
  bulbs('Bulbs & lamps'),
  automotive('Side steps & car parts'),
  other('Other');

  final String label;
  const DeviceCategory(this.label);

  static DeviceCategory fromName(String? name) => DeviceCategory.values
      .firstWhere((c) => c.name == name, orElse: () => DeviceCategory.other);
}
