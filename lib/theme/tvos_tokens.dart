/*
 * Arc TV - tvOS-style design tokens
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'package:flutter/material.dart';

/// Shared visual values for the tvOS-style redesign, on the 1920x1080 logical canvas.
/// Later phases (tiles, Top Shelf, dock, Control Center) read from here instead of
/// hard-coding numbers, so the look can be tuned in one place.
abstract final class TvosTokens {
  static const String fontFamily = 'Inter';

  // Colours (dark appearance).
  static const Color background = Color(0xFF0B0B0D);
  static const Color surface = Color(0xFF1C1C1E);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0x99FFFFFF);
  static const Color glassFill = Color(0x1FFFFFFF); // white @ 12%
  static const Color glassStroke = Color(0x38FFFFFF); // white @ 22%
  static const Color shelfScrim = Color(0x66000000); // black @ 40%

  // Radii.
  static const double tileRadius = 12;
  static const double dockRadius = 32;
  static const double panelRadius = 28;

  // Layout.
  static const double sideSafeArea = 90;
  static const double topSafeArea = 60;

  // Focus.
  static const double focusScale = 1.10;
  static const double focusShadowBlur = 30;
  static const Offset focusShadowOffset = Offset(0, 18);
  static const double restShadowBlur = 10;
  static const Offset restShadowOffset = Offset(0, 6);

  // Blur.
  // Logical px (x2 on the box).
  static const double dockBlurSigma = 20;
  static const double shelfBlurSigma = 25;

  // Motion.
  static const Duration focusDuration = Duration(milliseconds: 200);
  static const Curve focusCurve = Curves.easeOutCubic;
  static const Duration shelfCrossfade = Duration(milliseconds: 350);

  /// Text styles in the spirit of tvOS: bold titles, regular body, dimmed captions.
  static TextTheme textTheme(TextTheme base) => base
      .apply(fontFamily: fontFamily, bodyColor: textPrimary, displayColor: textPrimary)
      .copyWith(
        headlineMedium: base.headlineMedium?.copyWith(fontFamily: fontFamily, fontWeight: FontWeight.w700),
        titleLarge: base.titleLarge?.copyWith(fontFamily: fontFamily, fontWeight: FontWeight.w600),
        titleMedium: base.titleMedium?.copyWith(fontFamily: fontFamily, fontWeight: FontWeight.w500),
        bodySmall: base.bodySmall?.copyWith(fontFamily: fontFamily, color: textSecondary),
      );
}
