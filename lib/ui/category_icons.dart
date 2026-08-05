import 'package:flutter/material.dart';

import '../models/device_category.dart';

IconData categoryIcon(DeviceCategory category) => switch (category) {
      DeviceCategory.lightStrips => Icons.linear_scale,
      DeviceCategory.bulbs => Icons.lightbulb_outline,
      DeviceCategory.automotive => Icons.directions_car,
      DeviceCategory.other => Icons.devices_other,
    };
