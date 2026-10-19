/*
 * Arc TV - tvOS-style folder tile
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:typed_data';

import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/theme/tvos_tokens.dart';
import 'package:flauncher/widgets/folder_overlay.dart';
import 'package:flauncher/widgets/parallax_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A folder in the app grid: a frosted tile with up to nine of its apps' icons in a 3x3
/// grid. Focus lifts it like an app tile; Select opens [FolderOverlay].
class FolderTile extends StatefulWidget {
  final Category folder;
  final VoidCallback? onFocused;

  const FolderTile({super.key, required this.folder, this.onFocused});

  @override
  State<FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<FolderTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final preview = widget.folder.applications.take(9).toList(growable: false);
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        AnimatedScale(
          scale: _focused ? TvosTokens.focusScale : 1.0,
          duration: TvosTokens.focusDuration,
          curve: TvosTokens.focusCurve,
          child: ParallaxTile(
            focused: _focused,
            entryDirection: Offset.zero,
            child: AnimatedContainer(
              duration: TvosTokens.focusDuration,
              curve: TvosTokens.focusCurve,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(TvosTokens.tileRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _focused ? 0.55 : 0.35),
                    blurRadius: _focused ? TvosTokens.focusShadowBlur : TvosTokens.restShadowBlur,
                    offset: _focused ? TvosTokens.focusShadowOffset : TvosTokens.restShadowOffset,
                  ),
                ],
              ),
              child: Material(
                color: _focused ? const Color(0x33FFFFFF) : TvosTokens.glassFill,
                borderRadius: BorderRadius.circular(TvosTokens.tileRadius),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  focusColor: Colors.transparent,
                  onFocusChange: (focused) {
                    setState(() => _focused = focused);
                    if (focused) {
                      widget.onFocused?.call();
                      Scrollable.ensureVisible(
                        context,
                        alignment: 0.5,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  onTap: () => FolderOverlay.show(context, widget.folder),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    child: _MiniGrid(packageNames: preview.map((app) => app.packageName).toList()),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Folder name under the tile while focused, like app names.
        Positioned(
          left: 0,
          right: 0,
          bottom: -30,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _focused ? 1 : 0,
              duration: TvosTokens.focusDuration,
              child: Text(
                widget.folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: TvosTokens.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: TvosTokens.textPrimary,
                  shadows: [Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 6)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniGrid extends StatelessWidget {
  final List<String> packageNames;

  const _MiniGrid({required this.packageNames});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 6,
      crossAxisSpacing: 10,
      childAspectRatio: 5 / 3,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [for (final packageName in packageNames) _MiniIcon(packageName: packageName)],
    );
  }
}

class _MiniIcon extends StatefulWidget {
  final String packageName;

  const _MiniIcon({required this.packageName});

  @override
  State<_MiniIcon> createState() => _MiniIconState();
}

class _MiniIconState extends State<_MiniIcon> {
  late final Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    final apps = context.read<AppsService>();
    // Prefer the TV banner (what the full tile shows), fall back to the icon.
    _bytes = apps.getAppBanner(widget.packageName).then(
      (banner) => banner.isNotEmpty ? banner : apps.getAppIcon(widget.packageName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: bytes == null || bytes.isEmpty
              ? const ColoredBox(color: Color(0x22FFFFFF))
              : Image(image: ResizeImage(MemoryImage(bytes), width: 120), fit: BoxFit.cover),
        );
      },
    );
  }
}
