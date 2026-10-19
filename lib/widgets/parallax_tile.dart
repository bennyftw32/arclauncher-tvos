/*
 * Arc TV - tvOS-style parallax tile
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:math' as math;

import 'package:flauncher/theme/tvos_tokens.dart';
import 'package:flutter/material.dart';

/// Gives a focused tile the tvOS "settle": when focus arrives it tilts slightly in the
/// direction focus travelled, springs back flat, and a soft glare sweeps across it.
///
/// [entryDirection] is the direction focus moved to reach this tile (e.g. (1, 0) when the
/// user pressed Right). It is read when [focused] flips to true.
class ParallaxTile extends StatefulWidget {
  final bool focused;
  final Offset entryDirection;
  final double borderRadius;
  final Widget child;

  const ParallaxTile({
    super.key,
    required this.focused,
    required this.entryDirection,
    required this.child,
    this.borderRadius = TvosTokens.tileRadius,
  });

  @override
  State<ParallaxTile> createState() => _ParallaxTileState();
}

class _ParallaxTileState extends State<ParallaxTile> with SingleTickerProviderStateMixin {
  static const double _maxTilt = 5 * math.pi / 180; // 5 degrees
  static const Duration _settleDuration = Duration(milliseconds: 650);

  late final AnimationController _controller;
  Offset _direction = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _settleDuration, value: 1);
  }

  @override
  void didUpdateWidget(ParallaxTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused && !oldWidget.focused) {
      _direction = widget.entryDirection;
      _controller.forward(from: 0);
    } else if (!widget.focused && oldWidget.focused) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        // Tilt starts at full strength and springs back to flat with a small overshoot.
        final tilt = 1 - Curves.easeOutBack.transform(t);
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..rotateY(_direction.dx * tilt * _maxTilt)
          ..rotateX(-_direction.dy * tilt * _maxTilt);

        final showGlare = widget.focused && t < 1 && _direction != Offset.zero;
        return Transform(
          alignment: Alignment.center,
          transform: transform,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child!,
              if (showGlare)
                IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    child: _Glare(progress: Curves.easeOut.transform(t), direction: _direction),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A soft diagonal band of light that travels across the tile along [direction].
class _Glare extends StatelessWidget {
  final double progress;
  final Offset direction;

  const _Glare({required this.progress, required this.direction});

  @override
  Widget build(BuildContext context) {
    // Band centre moves from -0.4 to 1.4 of the tile so it enters and leaves fully.
    final centre = -0.4 + progress * 1.8;
    final opacity = 0.22 * math.sin(progress * math.pi);
    final dx = direction.dx == 0 ? 0.35 : direction.dx.sign;
    final dy = direction.dy == 0 ? 0.35 : direction.dy.sign;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-dx, -dy),
          end: Alignment(dx, dy),
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: opacity),
            Colors.white.withValues(alpha: 0),
          ],
          stops: [
            (centre - 0.25).clamp(0.0, 1.0),
            centre.clamp(0.0, 1.0),
            (centre + 0.25).clamp(0.0, 1.0),
          ],
        ),
      ),
    );
  }
}
