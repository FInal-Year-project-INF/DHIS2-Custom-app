// lib/utils/color_utils.dart
import 'package:flutter/material.dart';

/// Returns a color corresponding to a body temperature range.
Color getTemperatureColor(double? temperature) {
  if (temperature == null) return Colors.grey; // Unknown

  // Define temperature thresholds for better readability
  const hypothermia = 35.0;
  const belowNormal = 36.5;
  const normalUpper = 37.5;
  const slightFeverUpper = 38.0;
  const feverUpper = 39.5;

  if (temperature < hypothermia) {
    return Colors.blue.shade800; // Hypothermia
  } else if (temperature < belowNormal) {
    return Colors.blue.shade400; // Below normal
  } else if (temperature <= normalUpper) {
    return Colors.green; // Normal
  } else if (temperature <= slightFeverUpper) {
    return Colors.orange.shade300; // Slight fever
  } else if (temperature <= feverUpper) {
    return Colors.orange.shade700; // Fever
  } else {
    return Colors.red; // High fever
  }
}

