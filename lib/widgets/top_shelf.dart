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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Full-bleed art for the focused dock app, drawn behind the home screen like Apple TV's
/// Top Shelf. Shows the app's "continue watching" and featured items with their titles;
/// when the app publishes nothing, falls back to its banner, blurred and dimmed.
///
/// Up from the dock focuses the shelf (see [LauncherState.focusShelf]); Left/Right pages
/// through items, Select plays the current one, Down/Back returns to the dock.
class TopShelf extends StatefulWidget {
  /// Where the dock's top edge currently is on screen (null until laid out). The title and
  /// page dots sit just above it.
  final ValueListenable<double?> dockTop;

  const TopShelf({super.key, required this.dockTop});

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
  void initState() {
    super.initState();
    widget.dockTop.addListener(_onDockMoved);
  }

  @override
  void didUpdateWidget(TopShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dockTop != widget.dockTop) {
      oldWidget.dockTop.removeListener(_onDockMoved);
      widget.dockTop.addListener(_onDockMoved);
    }
  }

  @override
  void dispose() {
    widget.dockTop.removeListener(_onDockMoved);
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onDockMoved() => setState(() {});

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
    final launcherState = context.read<LauncherState>();

    final items = (await watchNext.shelfItemsFor(packageName))
        .where((item) {
          final uri = WatchNextService.shelfImageUri(item);
          return uri != null && !watchNext.hasPosterLoadFailed(uri);
        })
        .toList(growable: false);

    Uint8List? fallback;
    if (items.isEmpty) {
      fallback = await apps.getAppBanner(packageName);
      if (fallback.isEmpty) {
        fallback = await apps.getAppIcon(packageName);
      }
    } else {
      watchNext.ensurePosterLoaded(WatchNextService.shelfImageUri(items.first));
    }

    if (!mounted || _requestedPackage != packageName) {
      return;
    }
    launcherState.setShelfInteractive(items.isNotEmpty);
    setState(() {
      _content = _ShelfContent(packageName: packageName, items: items, fallbackImage: fallback);
    });
  }

  void _showIndex(int index) {
    final content = _content;
    if (content == null || index < 0 || index >= content.items.length || index == content.index) {
      return;
    }
    context.read<WatchNextService>().ensurePosterLoaded(WatchNextService.shelfImageUri(content.items[index]));
    // Warm the next one too so paging feels instant.
    if (index + 1 < content.items.length) {
      context.read<WatchNextService>().ensurePosterLoaded(WatchNextService.shelfImageUri(content.items[index + 1]));
    }
    setState(() => content.index = index);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final content = _content;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _showIndex((content?.index ?? 0) - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _showIndex((content?.index ?? 0) + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.gameButtonB) {
      context.read<LauncherState>().leaveShelf();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA)) {
      final item = content?.current;
      if (item != null) {
        context.read<WatchNextService>().launchItem(item);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final packageName = context.select<LauncherState, String?>((s) => s.shelfPackage);
    _onPackageChanged(packageName);
    final launcherState = context.read<LauncherState>();

    final content = _content;
    final currentUri = content?.current == null ? null : WatchNextService.shelfImageUri(content!.current!);
    // Rebuild when a poster we're waiting on finishes loading.
    final posterBytes = context.select<WatchNextService, Uint8List?>((s) => s.getCachedPoster(currentUri));

    // Title block ends 56px above the dock; the page dots sit in that gap.
    final screenHeight = MediaQuery.sizeOf(context).height;
    final dockTop = widget.dockTop.value ?? screenHeight * 0.55;
    final dotsBottomInset = screenHeight - dockTop + 22;
    final titleBottomInset = dotsBottomInset + 34;

    Widget child;
    if (content == null) {
      child = const SizedBox.expand(key: ValueKey('empty'));
    } else if (content.current != null && posterBytes != null) {
      child = _ArtShelf(
        key: ValueKey('art-${content.packageName}-$currentUri'),
        image: MemoryImage(posterBytes),
        title: content.current!.title,
        description: content.current!.description,
        titleBottomInset: titleBottomInset,
      );
    } else if (content.fallbackImage != null && content.fallbackImage!.isNotEmpty) {
      child = _FallbackShelf(
        key: ValueKey('fallback-${content.packageName}'),
        image: MemoryImage(content.fallbackImage!),
      );
    } else {
      child = const SizedBox.expand(key: ValueKey('empty'));
    }

    final interactive = context.select<LauncherState, bool>((s) => s.shelfInteractive);
    return Focus(
      focusNode: launcherState.shelfFocusNode,
      canRequestFocus: interactive,
      // Only reachable explicitly (Up from the dock), never by directional traversal: the
      // shelf covers the whole screen, so geometric traversal would grab it from anywhere.
      skipTraversal: true,
      onKeyEvent: _onKey,
      onFocusChange: (focused) {
        if (focused) {
          launcherState.setAppGridFocused(false);
        }
        setState(() {});
      },
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: TvosTokens.shelfCrossfade,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
              child: child,
            ),
            if (content != null && content.items.length > 1)
              Positioned(
                left: TvosTokens.sideSafeArea,
                bottom: dotsBottomInset,
                child: AnimatedOpacity(
                  opacity: launcherState.shelfFocusNode.hasFocus ? 1 : 0,
                  duration: TvosTokens.focusDuration,
                  child: _PageDots(count: content.items.length, index: content.index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShelfContent {
  final String packageName;
  final List<WatchNextItem> items;
  final Uint8List? fallbackImage;
  int index = 0;

  _ShelfContent({required this.packageName, required this.items, this.fallbackImage});

  WatchNextItem? get current => items.isEmpty ? null : items[index];
}

class _PageDots extends StatelessWidget {
  final int count;
  final int index;

  const _PageDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: TvosTokens.focusDuration,
          margin: const EdgeInsets.only(right: 8),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? TvosTokens.textPrimary : TvosTokens.textSecondary,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
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
