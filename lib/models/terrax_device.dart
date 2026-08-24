import 'device_category.dart';

/// A saved device. Identified by the platform BLE id ([id]) — on iOS this is a
/// per-app peripheral UUID, on Android the MAC. Never used for driver logic,
/// only to re-address the peripheral. Detection is by advertised name prefix +
/// service UUID (see lib/ble/detection.dart).
class TerraxDevice {
  /// Platform BLE remote id (opaque; differs between iOS and Android).
  final String id;

  /// Name seen in the advertisement when the device was added.
  final String advertisedName;

  /// User-editable display name.
  final String name;

  /// Which driver controls this device (see lib/ble/drivers/*).
  final String driverId;

  /// User-overridable category; driver supplies the default.
  final DeviceCategory category;

  const TerraxDevice({
    required this.id,
    required this.advertisedName,
    required this.name,
    required this.driverId,
    required this.category,
  });

  TerraxDevice copyWith({
    String? name,
    DeviceCategory? category,
    String? driverId,
  }) =>
      TerraxDevice(
        id: id,
        advertisedName: advertisedName,
        name: name ?? this.name,
        driverId: driverId ?? this.driverId,
        category: category ?? this.category,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'advertisedName': advertisedName,
        'name': name,
        'driverId': driverId,
        'category': category.name,
      };

  factory TerraxDevice.fromJson(Map<String, dynamic> json) => TerraxDevice(
        id: json['id'] as String,
        advertisedName: json['advertisedName'] as String? ?? '',
        name: json['name'] as String,
        driverId: json['driverId'] as String,
        category: DeviceCategory.fromName(json['category'] as String?),
      );
}
