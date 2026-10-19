/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flauncher/actions.dart';
import 'package:flauncher/app_image_type.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/theme/tvos_tokens.dart';
import 'package:flauncher/widgets/application_info_panel.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flauncher/widgets/parallax_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app.dart';
import '../models/category.dart';

const _validationKeys = [LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.gameButtonA];

// tvOS app icons are 5:3 (400x240 @1x).
const kAppCardAspectRatio = 5 / 3;
const kAppCardHorizontalPadding = 12.0;
const kAppCardVerticalPadding = 9.0;
const kLauncherSectionHorizontalPadding = 24.0;
const kAppNameLabelHeight = 24.0;

/// Row extent for a grid/dock line given the content width between section paddings.
double appCardRowExtentFromContentWidth(double contentWidth, {int columnCount = Category.ColumnsCount}) {
  final slotWidth = contentWidth / columnCount;
  return slotWidth / kAppCardAspectRatio;
}

/// Adjusted aspect ratio for grid cells that includes space for the app name label.
double appCardGridAspectRatio(double crossAxisExtent, int columnsCount) {
  final cellWidth = crossAxisExtent / columnsCount;
  return cellWidth / (cellWidth / kAppCardAspectRatio + kAppNameLabelHeight);
}

class AppCard extends StatefulWidget {
  final App application;
  final Category category;
  final bool autofocus;
  final void Function(AxisDirection) onMove;
  final VoidCallback onMoveEnd;
  final bool handleUpNavigationToSettings;
  final double scrollAlignment;
  final bool enforceAspectRatio;
  final VoidCallback? onFocused;
  final bool ensureVisibleOnFocus;
  final bool onlyScrollWhenNearBottom;
  /// Called when Up is pressed (and the card isn't being moved). Return true if handled.
  final bool Function()? onUpPressed;

  const AppCard({
    super.key,
    required this.application,
    required this.category,
    required this.autofocus,
    required this.onMove,
    required this.onMoveEnd,
    this.handleUpNavigationToSettings = false,
    this.scrollAlignment = 0.5,
    this.enforceAspectRatio = true,
    this.onFocused,
    this.ensureVisibleOnFocus = true,
    this.onlyScrollWhenNearBottom = false,
    this.onUpPressed,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> with SingleTickerProviderStateMixin {
  bool _moving = false;
  bool _clicked = false;
  bool _isFocused = false;
  bool _isTraditionalHighlightMode = false;
  bool _isHighlightAnimating = false;
  bool _animationEnabled = false;
  String? _accentColorHex;
  Color _accentColor = const Color(0xFF000000);
  DateTime? _lastMoveAt;
  DateTime? _lastEnsureVisibleAt;
  late FocusNode _focusNode;

  (AppImageType, ImageProvider)? _loadedImage;
  bool _imageLoadError = false;

  late final AnimationController _animation;

  late final CurvedAnimation _curvedAnimation;
  static const double _focusedScale = TvosTokens.focusScale;
  static const Duration _focusAnimationDuration = TvosTokens.focusDuration;

  // Centre of the last focused card, shared by all cards, so a newly focused card knows which
  // way focus travelled and can tilt in that direction.
  static Offset? _lastFocusCenter;
  Offset _entryDirection = Offset.zero;

  // Background for apps that only ship a square icon (no TV banner), sampled from the icon.
  Color? _iconBackground;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _curvedAnimation = CurvedAnimation(parent: _animation, curve: Curves.easeInOut);
    _focusNode = FocusNode();
    _isTraditionalHighlightMode = FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    FocusManager.instance.addHighlightModeListener(_focusHighlightModeChanged);
    _loadAppImage(Provider.of<AppsService>(context, listen: false));

    // Check if we need to restore focus/reorder mode after a move
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appsService = Provider.of<AppsService>(context, listen: false);
      if (appsService.pendingReorderFocusPackage == widget.application.packageName &&
          appsService.pendingReorderFocusCategoryId == widget.category.id) {
        appsService.clearPendingReorderFocusPackage();
        _focusNode.requestFocus();

        setState(() {
          _moving = true;
        });
      }
    });
  }

  @override
  void didUpdateWidget(AppCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final appsService = Provider.of<AppsService>(context, listen: false);

    if (oldWidget.application.packageName != widget.application.packageName) {
      _loadedImage = null;
      _imageLoadError = false;
      _loadAppImage(appsService);
    } else if (appsService.consumeDirtyImage(widget.application.packageName)) {
      _loadAppImage(appsService);
    }

    // Check for pending focus on update as well
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appsService = Provider.of<AppsService>(context, listen: false);
      if (appsService.pendingReorderFocusPackage == widget.application.packageName &&
          appsService.pendingReorderFocusCategoryId == widget.category.id) {
        appsService.clearPendingReorderFocusPackage();
        _focusNode.requestFocus();

        if (!_moving) {
          setState(() {
            _moving = true;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_focusHighlightModeChanged);
    _curvedAnimation.dispose();
    _animation.dispose();
    _focusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showAppNames = context.select<SettingsService, bool>((s) => s.showAppNamesBelowIcons);
    final (bool animationEnabled, String accentColorHex, bool showFocusBorders) = context.select<SettingsService, (bool, String, bool)>(
      (s) => (s.appHighlightAnimationEnabled, s.accentColorHex, s.showFocusBorders),
    );
    if (accentColorHex != _accentColorHex) {
      _accentColorHex = accentColorHex;
      _accentColor = Color(int.parse('FF$accentColorHex', radix: 16));
    }
    if (animationEnabled != _animationEnabled) {
      _animationEnabled = animationEnabled;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateHighlightAnimation();
      });
    }
    final appImageWidget = _appImage();
    final bool shouldHighlight = _shouldHighlight();

    return FocusKeyboardListener(
      onPressed: _onPressed,
      onLongPress: _onLongPress,
      child: AnimatedScale(
        scale: _clicked ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _clicked ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.passthrough,
                  children: [
                    _wrapAspectRatio(
                  RepaintBoundary(
                    child: _Jiggle(
                      active: _moving,
                      child: AnimatedScale(
                      // Moving (tvOS edit mode): stays lifted while it jiggles.
                      scale: _moving ? _focusedScale : (shouldHighlight ? _focusedScale : 1.0),
                      duration: _focusAnimationDuration,
                      alignment: Alignment.center,
                      curve: TvosTokens.focusCurve,
                      child: ParallaxTile(
                        focused: shouldHighlight && !_moving,
                        entryDirection: _entryDirection,
                        child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedContainer(
                            duration: _focusAnimationDuration,
                            curve: TvosTokens.focusCurve,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(TvosTokens.tileRadius),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: shouldHighlight ? 0.55 : 0.35),
                                  blurRadius: shouldHighlight ? TvosTokens.focusShadowBlur : TvosTokens.restShadowBlur,
                                  offset: shouldHighlight ? TvosTokens.focusShadowOffset : TvosTokens.restShadowOffset,
                                ),
                              ],
                            ),
                            child: Material(
                            color: _iconBackground ?? TvosTokens.surface,
                            borderRadius: BorderRadius.circular(TvosTokens.tileRadius),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                InkWell(
                                  focusNode: _focusNode,
                                  autofocus: widget.autofocus,
                                  focusColor: Colors.transparent,
                                  child: appImageWidget,
                                  onTap: () => _onPressed(LogicalKeyboardKey.enter),
                                  onLongPress: () => _onLongPress(LogicalKeyboardKey.enter),
                                  onFocusChange: (focused) {
                                    _handleFocusChange(context, focused);
                                  },
                                ),
                              ],
                            ),
                          ),
                          ),
                          if (shouldHighlight && showFocusBorders)
                            if (animationEnabled)
                              IgnorePointer(
                                child: RepaintBoundary(
                                  child: AnimatedBuilder(
                                    animation: _curvedAnimation,
                                    builder: (context, _) {
                                      final alpha = 0.4 + (_animation.value * 0.6);
                                      return _HighlightOutline(color: _accentColor.withValues(alpha: alpha));
                                    },
                                  ),
                                ),
                              )
                            else
                              IgnorePointer(child: RepaintBoundary(child: _HighlightOutline(color: _accentColor))),
                        ],
                      ),
                      ),
                    ),
                    ),
                ),
                ),
                    // tvOS shows the name only under the focused tile, in the gap below it.
                    if (!showAppNames)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: -30,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: shouldHighlight && !_moving ? 1 : 0,
                            duration: _focusAnimationDuration,
                            curve: TvosTokens.focusCurve,
                            child: _AppNameLabel(name: widget.application.name),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (showAppNames)
                Padding(padding: const EdgeInsets.only(top: 8.0), child: _AppNameLabel(name: widget.application.name)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadAppImage(AppsService service) async {
    try {
      Uint8List bytes = Uint8List(0);

      bytes = await service.getAppBanner(widget.application.packageName);
      AppImageType type = AppImageType.Banner;
      if (bytes.isEmpty) {
        type = AppImageType.Icon;
        bytes = await service.getAppIcon(widget.application.packageName);
      }
      final iconBackground = type == AppImageType.Icon ? await _sampleIconBackground(bytes) : null;
      if (mounted) {
        setState(() {
          _loadedImage = (type, ResizeImage(MemoryImage(bytes), width: 480));
          _iconBackground = iconBackground;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _imageLoadError = true);
      }
    }
  }

  /// Average colour of the icon's opaque pixels, darkened a little so a white logo stays
  /// readable — the plain "app colour" tile tvOS shows for icon-only apps.
  static Future<Color?> _sampleIconBackground(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 16, targetHeight: 16);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      codec.dispose();
      if (data == null) {
        return null;
      }
      int r = 0, g = 0, b = 0, n = 0;
      for (int i = 0; i + 3 < data.lengthInBytes; i += 4) {
        if (data.getUint8(i + 3) < 200) {
          continue;
        }
        r += data.getUint8(i);
        g += data.getUint8(i + 1);
        b += data.getUint8(i + 2);
        n++;
      }
      if (n == 0) {
        return null;
      }
      final average = Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
      return Color.lerp(average, Colors.black, 0.25);
    } catch (_) {
      return null;
    }
  }

  Widget _wrapAspectRatio(Widget child) {
    if (widget.enforceAspectRatio) {
      return AspectRatio(aspectRatio: kAppCardAspectRatio, child: child);
    }
    return child;
  }

  Widget _appImage() {
    App app = widget.application;

    if (_loadedImage != null) {
      final (type, image) = _loadedImage!;
      if (type == AppImageType.Banner) {
        return Ink.image(image: image, fit: BoxFit.cover);
      } else {
        // Icon-only app: the icon centred on its own colour, like a tvOS tile.
        return FractionallySizedBox(
          widthFactor: 0.42,
          heightFactor: 0.62,
          child: Ink.image(image: image, fit: BoxFit.contain),
        );
      }
    } else if (_imageLoadError) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Text(
            app.name,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
            maxLines: 3,
          ),
        ),
      );
    } else {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text("Loading"),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _focusHighlightModeChanged(FocusHighlightMode mode) {
    final nextMode = mode == FocusHighlightMode.traditional;
    if (nextMode == _isTraditionalHighlightMode) {
      return;
    }
    setState(() {
      _isTraditionalHighlightMode = nextMode;
    });
    _updateHighlightAnimation();
  }

  bool _shouldHighlight() {
    return _isTraditionalHighlightMode && _isFocused;
  }

  void _handleFocusChange(BuildContext context, bool focused) {
    if (focused) {
      _entryDirection = _focusTravelDirection(context);
    }
    if (_isFocused != focused) {
      setState(() {
        _isFocused = focused;
      });
    }
    _updateHighlightAnimation();

    if (!focused) {
      return;
    }

    final now = DateTime.now();
    if (_lastEnsureVisibleAt != null && now.difference(_lastEnsureVisibleAt!).inMilliseconds < 120) {
      return;
    }
    _lastEnsureVisibleAt = now;
    if (widget.ensureVisibleOnFocus) {
      _ensureVisibleIfNeeded(
        context,
        // This specific alignment value is not only
        // to center the focused card in the row while
        // scrolling, but to prevent the topmost category
        // title to be hidden by the content above it when
        // scrolling from the app bar. How it relates to this,
        // I don't know
        alignment: widget.scrollAlignment,
        onlyWhenNearBottom: widget.onlyScrollWhenNearBottom,
      );
    }
    widget.onFocused?.call();
  }

  /// Unit step along the dominant axis from the previously focused card to this one,
  /// e.g. (1, 0) after pressing Right. Zero for the first focus.
  Offset _focusTravelDirection(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return Offset.zero;
    }
    final centre = box.localToGlobal(box.size.center(Offset.zero));
    final previous = _lastFocusCenter;
    _lastFocusCenter = centre;
    if (previous == null) {
      return Offset.zero;
    }
    final delta = centre - previous;
    if (delta.distance < 1) {
      return Offset.zero;
    }
    return delta.dx.abs() >= delta.dy.abs()
        ? Offset(delta.dx.sign, 0)
        : Offset(0, delta.dy.sign);
  }

  void _updateHighlightAnimation() {
    _setHighlightAnimation(_shouldHighlight() && _animationEnabled);
  }

  void _setHighlightAnimation(bool shouldAnimate) {
    if (_isHighlightAnimating == shouldAnimate) {
      return;
    }
    _isHighlightAnimating = shouldAnimate;
    if (shouldAnimate) {
      _animation.repeat(reverse: true);
    } else {
      _animation.stop();
    }
  }

  void _ensureVisibleIfNeeded(BuildContext context, {required double alignment, bool onlyWhenNearBottom = false}) {
    final renderObject = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    if (renderObject == null || scrollable == null) {
      return;
    }

    final viewport = RenderAbstractViewport.of(renderObject);

    final position = scrollable.position;
    const minDeltaToScroll = 24.0;
    if (onlyWhenNearBottom &&
        (position.axisDirection == AxisDirection.down || position.axisDirection == AxisDirection.up)) {
      const topEdgePadding = kToolbarHeight + 24.0;
      const bottomEdgePadding = 96.0;
      final topTargetOffset = (viewport.getOffsetToReveal(renderObject, 0).offset - topEdgePadding).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (position.pixels - topTargetOffset >= minDeltaToScroll) {
        position.animateTo(
          topTargetOffset,
          curve: Curves.easeInOut,
          duration: const Duration(milliseconds: 220),
        );
        return;
      }

      final bottomTargetOffset = (viewport.getOffsetToReveal(renderObject, 1).offset + bottomEdgePadding).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (bottomTargetOffset - position.pixels < minDeltaToScroll) {
        return;
      }

      position.animateTo(
        bottomTargetOffset,
        curve: Curves.easeInOut,
        duration: const Duration(milliseconds: 220),
      );
      return;
    }

    final targetOffset = viewport.getOffsetToReveal(renderObject, alignment).offset;
    if ((targetOffset - position.pixels).abs() < minDeltaToScroll) {
      return;
    }

    Scrollable.ensureVisible(
      context,
      alignment: alignment,
      curve: Curves.easeInOut,
      duration: const Duration(milliseconds: 220),
    );
  }

  KeyEventResult _onPressed(LogicalKeyboardKey? key) {
    if (_moving) {
      if (_validationKeys.contains(key) || key == LogicalKeyboardKey.escape) {
        _lastMoveAt = null;
        setState(() => _moving = false);
        widget.onMoveEnd();
      } else {
        final now = DateTime.now();
        if (_lastMoveAt != null && now.difference(_lastMoveAt!).inMilliseconds < 60) {
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.arrowLeft) {
          widget.onMove(AxisDirection.left);
        } else if (key == LogicalKeyboardKey.arrowUp) {
          widget.onMove(AxisDirection.up);
        } else if (key == LogicalKeyboardKey.arrowRight) {
          widget.onMove(AxisDirection.right);
        } else if (key == LogicalKeyboardKey.arrowDown) {
          widget.onMove(AxisDirection.down);
        } else {
          return KeyEventResult.ignored;
        }

        _lastMoveAt = now;
        final nowForScroll = DateTime.now();
        if (_lastEnsureVisibleAt == null || nowForScroll.difference(_lastEnsureVisibleAt!).inMilliseconds >= 120) {
          _lastEnsureVisibleAt = nowForScroll;
          WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisibleIfNeeded(context, alignment: 0.1));
        }
      }

      return KeyEventResult.handled;
    } else if (_validationKeys.contains(key)) {
      if (!_clicked) {
        setState(() => _clicked = true);
        Future.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          context.read<AppsService>().launchApp(widget.application);
          // Reset after a short delay so it looks normal when user returns
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() => _clicked = false);
            }
          });
        });
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp && (widget.onUpPressed?.call() ?? false)) {
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp && widget.handleUpNavigationToSettings) {
      Actions.invoke(context, const MoveFocusToSettingsIntent());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onLongPress(LogicalKeyboardKey? key) {
    if (!_moving && (key == null || longPressableKeys.contains(key))) {
      _showPanel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _showPanel() async {
    final result = await showDialog<ApplicationInfoPanelResult>(
      context: context,
      builder: (context) => ApplicationInfoPanel(category: widget.category, application: widget.application),
    );
    if (result == ApplicationInfoPanelResult.reorderApp) {
      // The menu may have been opened by touch, which doesn't focus the tile; the arrow keys
      // that move it only reach a focused tile.
      _focusNode.requestFocus();
      setState(() => _moving = true);
    }
  }
}

/// tvOS edit-mode "jiggle": a small, quick back-and-forth rotation while a tile is being moved.
class _Jiggle extends StatefulWidget {
  final bool active;
  final Widget child;

  const _Jiggle({required this.active, required this.child});

  @override
  State<_Jiggle> createState() => _JiggleState();
}

class _JiggleState extends State<_Jiggle> with SingleTickerProviderStateMixin {
  static const double _amplitude = 1.5 * 3.14159265 / 180; // 1.5 degrees

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Jiggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => Transform.rotate(
        angle: (Curves.easeInOut.transform(_controller.value) * 2 - 1) * _amplitude,
        child: child,
      ),
    );
  }
}

class _AppNameLabel extends StatelessWidget {
  final String name;

  const _AppNameLabel({required this.name});

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      style: const TextStyle(
        fontFamily: TvosTokens.fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: TvosTokens.textPrimary,
        shadows: [Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 6)],
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      textAlign: TextAlign.center,
    );
  }
}

class _HighlightOutline extends StatelessWidget {
  final Color color;

  const _HighlightOutline({required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: 1),
          ),
        ),
      ],
    );
  }
}
