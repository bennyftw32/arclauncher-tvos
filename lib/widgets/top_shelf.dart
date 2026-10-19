/*
 * Arc TV - tvOS-style Top Shelf
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flauncher/models/watch_next_item.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/theme/tvos_tokens.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Full-bleed art for the focused dock app, drawn behind the home screen like Apple TV's
/// Top Shelf. Shows the app's first "continue watching" or featured item with its title;
/// when the app publishes nothing, falls back to its banner, blurred and dimmed.
class TopShelf extends StatefulWidget {
  /// Distance from the bottom of the screen to the title block (keeps it above the dock).
  final double titleBottomInset;

  const TopShelf({super.key, required this.titleBottomInset});

  @override
  State<TopShelf> createState() => _TopShelfState();
}

class _TopShelfState extends State<TopShelf> {
  // Moving quickly across the dock shouldn't load art for every app passed over.
  static const Duration _debounce = Duration(milliseconds: 150);

  Timer? _debounceTimer;
  String? _requestedPackage;
  _ShelfContent? _content;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onPackageChanged(String? packageName) {
    if (packageName == null || packageName == _requestedPackage) {
      return;
    }
    _requestedPackage = packageName;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => _load(packageName));
  }

  Future<void> _load(String packageName) async {
    final watchNext = context.read<WatchNextService>();
    final apps = context.read<AppsService>();

    final items = await watchNext.shelfItemsFor(packageName);
    WatchNextItem? item;
    String? imageUri;
    for (final candidate in items) {
      final uri = WatchNextService.shelfImageUri(candidate);
      if (uri != null && !watchNext.hasPosterLoadFailed(uri)) {
        item = candidate;
        imageUri = uri;
        break;
      }
    }
    Uint8List? fallback;
    if (item == null) {
      fallback = await apps.getAppBanner(packageName);
      if (fallback.isEmpty) {
        fallback = await apps.getAppIcon(packageName);
      }
    } else {
      watchNext.ensurePosterLoaded(imageUri);
    }

    if (!mounted || _requestedPackage != packageName) {
      return;
    }
    setState(() {
      _content = _ShelfContent(packageName: packageName, item: item, imageUri: imageUri, fallbackImage: fallback);
    });
  }

  @override
  Widget build(BuildContext context) {
    final packageName = context.select<LauncherState, String?>((s) => s.shelfPackage);
    _onPackageChanged(packageName);

    final content = _content;
    // Rebuild when a poster we're waiting on finishes loading.
    final posterBytes = context.select<WatchNextService, Uint8List?>(
      (s) => s.getCachedPoster(content?.imageUri),
    );

    Widget child;
    if (content == null) {
      child = const SizedBox.expand(key: ValueKey('empty'));
    } else if (content.item != null && posterBytes != null) {
      child = _ArtShelf(
        key: ValueKey('art-${content.packageName}-${content.imageUri}'),
        image: MemoryImage(posterBytes),
        title: content.item!.title,
        description: content.item!.description,
        titleBottomInset: widget.titleBottomInset,
      );
    } else if (content.fallbackImage != null && content.fallbackImage!.isNotEmpty) {
      child = _FallbackShelf(
        key: ValueKey('fallback-${content.packageName}'),
        image: MemoryImage(content.fallbackImage!),
      );
    } else {
      child = const SizedBox.expand(key: ValueKey('empty'));
    }

    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: TvosTokens.shelfCrossfade,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
        child: child,
      ),
    );
  }
}

class _ShelfContent {
  final String packageName;
  final WatchNextItem? item;
  final String? imageUri;
  final Uint8List? fallbackImage;

  const _ShelfContent({required this.packageName, this.item, this.imageUri, this.fallbackImage});
}

/// Item art filling the screen, darkened toward the bottom and left so the title and dock read.
class _ArtShelf extends StatelessWidget {
  final ImageProvider image;
  final String title;
  final String? description;
  final double titleBottomInset;

  const _ArtShelf({
    super.key,
    required this.image,
    required this.title,
    required this.description,
    required this.titleBottomInset,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: ResizeImage(image, width: (size.width * dpr).round(), policy: ResizeImagePolicy.fit),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.45, 1.0],
              colors: [Color(0x00000000), Color(0x33000000), Color(0xE6000000)],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.center,
              colors: [Color(0x8C000000), Color(0x00000000)],
            ),
          ),
        ),
        Positioned(
          left: TvosTokens.sideSafeArea,
          right: size.width * 0.4,
          bottom: titleBottomInset,
          // The shelf sits outside the Scaffold, so give the text a plain default style
          // (otherwise Flutter's missing-Material debug underline shows).
          child: DefaultTextStyle(
            style: const TextStyle(decoration: TextDecoration.none),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: TvosTokens.fontFamily,
                  fontSize: 44,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: TvosTokens.textPrimary,
                ),
              ),
              if (description != null && description!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: TvosTokens.fontFamily,
                    fontSize: 20,
                    height: 1.3,
                    fontWeight: FontWeight.w400,
                    color: TvosTokens.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          ),
        ),
      ],
    );
  }
}

/// The app's own banner, enlarged, blurred and dimmed: a colour wash in the app's palette.
class _FallbackShelf extends StatelessWidget {
  final ImageProvider image;

  const _FallbackShelf({super.key, required this.image});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60, tileMode: TileMode.clamp),
          child: Image(image: ResizeImage(image, width: 320), fit: BoxFit.cover),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x59000000), Color(0xCC000000)],
            ),
          ),
        ),
      ],
    );
  }
}
