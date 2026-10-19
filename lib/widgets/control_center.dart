/*
 * Arc TV - tvOS-style Control Center
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/theme/tvos_tokens.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Apple TV's Control Center: a frosted column down the right edge with the time and quick
/// actions. Opened by holding Home (see ArcAccessibilityService) or from Arc's settings.
class ControlCenter extends StatelessWidget {
  const ControlCenter({super.key});

  static bool _open = false;

  static Future<void> show(BuildContext context) async {
    if (_open) {
      return;
    }
    _open = true;
    try {
      await showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Control Center',
        barrierColor: const Color(0x33000000),
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => const ControlCenter(),
        transitionBuilder: (context, animation, _, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween(begin: const Offset(0.35, 0), end: Offset.zero).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
      );
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final channel = context.read<FLauncherChannel>();
    final apps = context.read<AppsService>();

    void close() => Navigator.of(context).pop();

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(TvosTokens.panelRadius),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Material(
              color: const Color(0xB31C1C1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TvosTokens.panelRadius),
                side: const BorderSide(color: TvosTokens.glassStroke),
              ),
              child: SizedBox(
                width: 300,
                height: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Clock(),
                      const SizedBox(height: 20),
                      _ControlButton(
                        icon: Icons.power_settings_new_rounded,
                        label: 'Sleep',
                        autofocus: true,
                        onPressed: () async {
                          close();
                          // Falls back to the screensaver when the Home-button service is off.
                          if (!await channel.sleepNow()) {
                            await apps.startAmbientMode();
                          }
                        },
                      ),
                      _ControlButton(
                        icon: Icons.landscape_rounded,
                        label: 'Screensaver',
                        onPressed: () {
                          close();
                          apps.startAmbientMode();
                        },
                      ),
                      _ControlButton(
                        icon: Icons.wifi_rounded,
                        label: 'Wi-Fi',
                        onPressed: () {
                          close();
                          channel.openWifiSettings();
                        },
                      ),
                      _ControlButton(
                        icon: Icons.settings_rounded,
                        label: 'Settings',
                        onPressed: () {
                          close();
                          apps.openSettings();
                        },
                      ),
                      _ControlButton(
                        icon: Icons.tune_rounded,
                        label: 'Arc TV Settings',
                        onPressed: () {
                          close();
                          showDialog(context: context, builder: (_) => const SettingsPanel());
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat.jm(locale).format(_now),
          style: const TextStyle(
            fontFamily: TvosTokens.fontFamily,
            fontSize: 40,
            height: 1.0,
            fontWeight: FontWeight.w600,
            color: TvosTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          DateFormat.MMMMEEEEd(locale).format(_now),
          style: const TextStyle(
            fontFamily: TvosTokens.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: TvosTokens.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// A Control Center row: dim glass at rest; on focus it turns white with dark text and lifts,
/// the way tvOS highlights a focused control.
class _ControlButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;

  const _ControlButton({required this.icon, required this.label, required this.onPressed, this.autofocus = false});

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final foreground = _focused ? const Color(0xFF1C1C1E) : TvosTokens.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedScale(
        scale: _focused ? 1.04 : 1.0,
        duration: TvosTokens.focusDuration,
        curve: TvosTokens.focusCurve,
        child: Material(
          color: _focused ? Colors.white : TvosTokens.glassFill,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            autofocus: widget.autofocus,
            focusColor: Colors.transparent,
            onFocusChange: (focused) => setState(() => _focused = focused),
            onTap: widget.onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(widget.icon, size: 22, color: foreground),
                  const SizedBox(width: 14),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: TvosTokens.fontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
