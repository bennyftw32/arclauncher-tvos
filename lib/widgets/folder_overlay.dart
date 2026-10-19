/*
 * Arc TV - tvOS-style folder overlay
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:ui' as ui;

import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/theme/tvos_tokens.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// An opened folder: the home screen blurs and dims, the folder name sits on top, and the
/// folder's apps are laid out 5 per row. Back closes it.
class FolderOverlay extends StatelessWidget {
  final int folderId;

  const FolderOverlay({super.key, required this.folderId});

  static Future<void> show(BuildContext context, Category folder) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: folder.name,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => FolderOverlay(folderId: folder.id),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Look the folder up live so apps removed from it disappear immediately.
    final folder = context.select<AppsService, Category?>(
      (service) => service.categories.where((c) => c.id == folderId).firstOrNull,
    );
    final apps = folder?.applications ?? const [];
    final columns = Category.ColumnsCount;

    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: TvosTokens.shelfBlurSigma, sigmaY: TvosTokens.shelfBlurSigma),
      child: Material(
        color: const Color(0x99000000),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: TvosTokens.sideSafeArea, vertical: TvosTokens.topSafeArea),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                folder?.name ?? '',
                style: const TextStyle(
                  fontFamily: TvosTokens.fontFamily,
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: TvosTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: apps.isEmpty
                    ? const Center(
                        child: Text(
                          'This folder is empty. Long-press an app and choose Add to Category to fill it.',
                          style: TextStyle(fontFamily: TvosTokens.fontFamily, fontSize: 20, color: TvosTokens.textSecondary),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.only(bottom: 40),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          childAspectRatio: kAppCardAspectRatio,
                          mainAxisSpacing: 28,
                        ),
                        itemCount: apps.length,
                        itemBuilder: (context, index) => Padding(
                          key: ValueKey(apps[index].packageName),
                          padding: const EdgeInsets.symmetric(
                            horizontal: kAppCardHorizontalPadding,
                            vertical: kAppCardVerticalPadding,
                          ),
                          child: AppCard(
                            category: folder!,
                            application: apps[index],
                            autofocus: index == 0,
                            enforceAspectRatio: false,
                            onMove: (direction) => _move(context, folder, index, direction),
                            onMoveEnd: () => context.read<AppsService>().saveApplicationOrderInCategory(folder),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _move(BuildContext context, Category folder, int index, AxisDirection direction) {
    final columns = Category.ColumnsCount;
    final count = folder.applications.length;
    int? newIndex;
    switch (direction) {
      case AxisDirection.left:
        if (index > 0) newIndex = index - 1;
      case AxisDirection.right:
        if (index < count - 1) newIndex = index + 1;
      case AxisDirection.up:
        if (index - columns >= 0) newIndex = index - columns;
      case AxisDirection.down:
        if (index + columns < count) newIndex = index + columns;
    }
    if (newIndex == null) {
      return;
    }
    final appsService = context.read<AppsService>();
    final moving = folder.applications[index];
    appsService.reorderApplication(folder, index, newIndex);
    appsService.setPendingReorderFocus(moving.packageName, folder.id);
  }
}
