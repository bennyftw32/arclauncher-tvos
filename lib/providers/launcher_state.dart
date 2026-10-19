/*
 * FLauncher
 * Copyright (C) 2021  Oscar Rojas
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

import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../widgets/settings/back_button_actions.dart';
import 'apps_service.dart';

class LauncherState extends ChangeNotifier
{
  bool _isDefaultLauncher;
  bool _launcherVisible;
  bool _appGridFocused;

  bool get isDefaultLauncher => _isDefaultLauncher;
  bool get launcherVisible => _launcherVisible;
  bool get appGridFocused => _appGridFocused;

  // Package of the dock app the Top Shelf is showing. Kept when focus leaves the dock so the
  // shelf doesn't flash empty; the grid's blur layer covers it instead, as on tvOS.
  String? _shelfPackage;
  String? get shelfPackage => _shelfPackage;

  LauncherState() : _isDefaultLauncher = false, _launcherVisible = true, _appGridFocused = false;

  // The Top Shelf can take focus (Up from the dock) when it is showing real items.
  final FocusNode shelfFocusNode = FocusNode(debugLabel: 'TopShelf');
  FocusNode? _shelfReturnFocus;
  bool _shelfInteractive = false;
  bool get shelfInteractive => _shelfInteractive;

  void setShelfInteractive(bool value) {
    if (_shelfInteractive == value) {
      return;
    }
    _shelfInteractive = value;
    notifyListeners();
  }

  /// Moves focus from the dock into the Top Shelf. Returns false if the shelf has nothing to focus.
  bool focusShelf() {
    if (!_shelfInteractive) {
      return false;
    }
    _shelfReturnFocus = FocusManager.instance.primaryFocus;
    shelfFocusNode.requestFocus();
    return true;
  }

  /// Gives focus back to the dock app the user came from.
  void leaveShelf() {
    final target = _shelfReturnFocus;
    _shelfReturnFocus = null;
    if (target != null && target.canRequestFocus && target.context != null) {
      target.requestFocus();
    } else {
      shelfFocusNode.unfocus();
    }
  }

  void setShelfPackage(String packageName) {
    if (_shelfPackage == packageName) {
      return;
    }
    _shelfPackage = packageName;
    notifyListeners();
  }

  void toggleLauncherVisibility() {
    _launcherVisible = !_launcherVisible;
    notifyListeners();
  }

  void setAppGridFocused(bool value) {
    if (_appGridFocused == value) {
      return;
    }
    _appGridFocused = value;
    notifyListeners();
  }

  Future<void> refresh(AppsService appsService) async {
    _isDefaultLauncher = await appsService.isDefaultLauncher();
    notifyListeners();
  }

  void handleBackNavigation(BuildContext context) {
    AppsService appsService = context.read<AppsService>();
    LauncherState launcherState = context.read<LauncherState>();
    SettingsService settingsService = context.read<SettingsService>();

    if (kDebugMode || launcherState.isDefaultLauncher) {
      launcherState.refresh(appsService);
      String action = settingsService.backButtonAction;

      switch (action) {
        case BACK_BUTTON_ACTION_CLOCK:
          launcherState.toggleLauncherVisibility();
          break;
        case BACK_BUTTON_ACTION_SCREENSAVER:
          appsService.startAmbientMode();
          break;
      }
    }
    else {
      SystemNavigator.pop();
    }
  }
}