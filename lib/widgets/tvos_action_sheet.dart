/*
 * Arc TV - tvOS-style action sheet
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:ui' as ui;

import 'package:flauncher/actions.dart';
import 'package:flauncher/theme/tvos_tokens.dart';
import 'package:flutter/material.dart';

/// A centred frosted-glass panel for menus (tvOS action sheet), used in place of Arc's
/// left side panel for the app long-press menu.
class TvosActionSheet extends StatelessWidget {
  final Widget child;
  final double width;

  // Logical pixels; Arc lays out on a 960x540 canvas at 2x on a 1080p/4K box.
  const TvosActionSheet({super.key, required this.child, this.width = 360});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.8;
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TvosTokens.panelRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Material(
            color: const Color(0xCC1C1C1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TvosTokens.panelRadius),
              side: const BorderSide(color: TvosTokens.glassStroke),
            ),
            child: Container(
              width: width,
              height: height,
              padding: const EdgeInsets.all(28),
              child: Actions(
                actions: {BackIntent: BackAction(context)},
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
