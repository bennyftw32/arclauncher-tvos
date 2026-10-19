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

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flauncher/actions.dart';
import 'package:flauncher/custom_traversal_policy.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flauncher/widgets/cached_blur_backdrop.dart';
import 'package:flauncher/widgets/category_clean_row.dart';
import 'package:flauncher/widgets/category_row.dart';
import 'package:flauncher/widgets/launcher_alternative_view.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/widgets/control_center.dart';
import 'package:flauncher/widgets/folder_tile.dart';
import 'package:flauncher/widgets/top_shelf.dart';
import 'package:flauncher/theme/tvos_tokens.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/widgets/wallpaper_video_background.dart';
import 'package:flauncher/widgets/watch_next_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';

import 'models/app.dart';
import 'models/category.dart';

const _kDockOuterPadding = EdgeInsets.only(
  left: kLauncherSectionHorizontalPadding,
  right: kLauncherSectionHorizontalPadding,
  top: 10,
  bottom: 16,
);

// Where the dock's top edge sits, as a fraction of screen height.
const double _kDockTopFraction = 0.66; // lands the dock at ~58% once the initial scroll settles


// Extra room inside the dock below the tiles for the focused app's name.
const double _kDockLabelSpace = 24;

class FLauncher extends StatefulWidget {
  const FLauncher({super.key});

  @override
  State<FLauncher> createState() => _FLauncherState();
}

class _FLauncherState extends State<FLauncher> with WidgetsBindingObserver {
  final GlobalKey<FocusAwareAppBarState> _appBarKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _dockKey = GlobalKey();
  // On-screen top edge of the dock, for placing the Top Shelf title above it.
  final ValueNotifier<double?> _dockTop = ValueNotifier(null);
  // Wraps the dock so Home can send focus back to it; remembers the dock tile focused last.
  final FocusNode _dockFocus = FocusNode(debugLabel: 'dock', skipTraversal: true, canRequestFocus: false);
  FocusNode? _lastDockFocus;
  final GlobalKey _dockContentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_updateDockTop);

    // Holding Home opens Control Center (via ArcAccessibilityService).
    final channel = context.read<FLauncherChannel>();
    channel.setControlCenterListener(() {
      if (mounted) ControlCenter.show(context);
    }, onHome: _onHomePressed);
    FocusManager.instance.addListener(_rememberDockFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await channel.consumeControlCenterRequest() && mounted) {
        ControlCenter.show(context);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_rememberDockFocus);
    _dockFocus.dispose();
    _scrollController.dispose();
    _dockTop.dispose();
    _dockSettled.dispose();
    super.dispose();
  }

  void _rememberDockFocus() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus != _dockFocus && focus.ancestors.contains(_dockFocus)) {
      _lastDockFocus = focus;
    }
  }

  /// tvOS: Home closes whatever is open and puts focus back on the dock, page scrolled to the top.
  void _onHomePressed() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    // After the pop, so the closed route's focus restoration doesn't win.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The dock rebuilds its tiles (and their focus nodes) when apps change, so only reuse the
      // remembered tile if it's still one of the dock's live nodes.
      final tiles = _dockFocus.traversalDescendants.toList();
      final target = tiles.contains(_lastDockFocus) ? _lastDockFocus : tiles.firstOrNull;
      target?.requestFocus();
    });
    // Nothing may have changed on screen, so make sure that frame actually comes.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _updateDockTop() {
    final box = _dockKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) {
      return;
    }
    _dockTop.value = box.localToGlobal(Offset.zero).dy + _kDockOuterPadding.top;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<WatchNextService>().refreshPermissionAndItems();
    }
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: <Type, Action<Intent>>{
      MoveFocusToSettingsIntent: CallbackAction<MoveFocusToSettingsIntent>(
        onInvoke: (_) => _appBarKey.currentState?.focusSettings(),
      ),
    },
    child: FocusTraversalGroup(
      policy: RowByRowTraversalPolicy(),
      child: Stack(
        children: [
          RepaintBoundary(
            child: Consumer<WallpaperService>(
              builder: (_, wallpaperService, __) => _wallpaper(context, wallpaperService),
            ),
          ),
          // Top Shelf sits between the wallpaper and the grid's blur layer, so moving into the
          // grid blurs it away the way tvOS does.
          Positioned.fill(child: RepaintBoundary(child: TopShelf(dockTop: _dockTop))),
          Selector3<LauncherState, SettingsService, WallpaperService, (bool, bool, bool)>(
            selector: (_, launcherState, settings, wallpaperService) => (
              launcherState.appGridFocused,
              settings.backgroundBlurDisabled,
              wallpaperService.wallpaperVideoFile != null,
            ),
            builder: (_, data, __) {
              final (appGridFocused, blurDisabled, hasVideoWallpaper) = data;
              if (hasVideoWallpaper) {
                return const SizedBox.shrink();
              }
              return Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: appGridFocused && !blurDisabled ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: const CachedBlurLayer(sigma: 10),
                  ),
                ),
              );
            },
          ),
          Consumer<LauncherState>(
            builder:
                (_, state, child) => Visibility(
                  replacement: const Center(child: AlternativeLauncherView()),
                  visible: state.launcherVisible,
                  child: child!,
                ),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: FocusAwareAppBar(key: _appBarKey),
              // (initialized (data.$1), layoutVersion (data.$2), showAppNamesBelowIcons (data.$3))
              body: Selector2<AppsService, SettingsService, (bool, int, bool)>(
                selector: (_, appsService, settingsService) =>
                    (appsService.initialized, appsService.layoutVersion, settingsService.showAppNamesBelowIcons),
                builder: (context, data, _) {
                  if (data.$1) {
                    return _tvOSLayout(context, context.read<AppsService>(), showAppNames: data.$3);
                  } else {
                    return _emptyState(context);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _setAppGridFocused(bool focused) {
    context.read<LauncherState>().setAppGridFocused(focused);
  }

  // The dock's live blur (over Top Shelf art) is expensive to recompute while the page scrolls,
  // so it only runs once the page has settled at the top; otherwise the cached wallpaper blur is used.
  final ValueNotifier<bool> _dockSettled = ValueNotifier(true);

  void _onAppGridFocused({VoidCallback? onFirstSectionFocused}) {
    _dockSettled.value = false;
    _setAppGridFocused(true);
    onFirstSectionFocused?.call();
  }

  void _onHomeSectionFocused() {
    _setAppGridFocused(false);
    // tvOS: with the dock focused the page rests at the top, dock under the Top Shelf.
    if (_scrollController.hasClients && _scrollController.offset > 1) {
      _dockSettled.value = false;
      _scrollController
          .animateTo(0, duration: const Duration(milliseconds: 260), curve: Curves.easeInOutCubic)
          .whenComplete(() => _dockSettled.value = true);
    } else {
      _dockSettled.value = true;
    }
  }

  Widget _tvOSLayout(BuildContext context, AppsService appsService, {required bool showAppNames}) {
    final favoritesCategory = appsService.categories.firstWhereOrNull((c) => c.name == 'Favorites');
    final favoriteApps = favoritesCategory?.applications ?? const [];

    // Folders don't get their own section; they appear as tiles at the end of the main grid.
    final folders = appsService.launcherSections
        .whereType<Category>()
        .where((category) => category.type == CategoryType.folder)
        .toList(growable: false);
    final otherSections =
        appsService.launcherSections.where((section) {
          if (section is Category && section.name == 'Favorites') return false;
          if (section is Category && section.type == CategoryType.folder) return false;
          return true;
        }).toList();

    final showWatchNextSection = context.select<SettingsService, bool>((s) => s.showWatchNextSection);
    final watchNextVisible = context.select<WatchNextService, bool>((s) => s.hasVisibleSection);
    final reserveWatchNextSpace = showWatchNextSection && watchNextVisible;

    if (favoriteApps.isEmpty && otherSections.isEmpty) return _emptyState(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateDockTop());

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (favoriteApps.isNotEmpty || showWatchNextSection) ...[
          SliverToBoxAdapter(
            child: SizedBox(
              height: reserveWatchNextSpace
                  ? MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - kToolbarHeight - 410
                  // tvOS: the dock's top edge sits a little below the middle, under the Top Shelf.
                  : MediaQuery.of(context).size.height * _kDockTopFraction - kToolbarHeight - _kDockOuterPadding.top,
            ),
          ),
          if (showWatchNextSection)
            SliverToBoxAdapter(
              child: WatchNextRow(
                isFirstSection: false,
                isAboveDock: true,
                onItemFocused: _onHomeSectionFocused,
              ),
            ),
          if (favoriteApps.isNotEmpty)
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _dockKey,
                child: Focus(
                  focusNode: _dockFocus,
                  child: Padding(
                    padding: _kDockOuterPadding,
                    child: _dock(
                      context,
                      favoritesCategory!,
                      favoriteApps,
                      appsService,
                      handleUpNavigationToSettings: !reserveWatchNextSpace,
                    ),
                  ),
                ),
              ),
            ),
        ],
        ..._buildSectionSlivers(
          otherSections,
          folders: folders,
          firstCategoryAlreadyFound: favoriteApps.isNotEmpty,
          showAppNames: showAppNames,
          onFirstSectionFocused: favoriteApps.isNotEmpty ? _scrollDockToTop : null,
        ),
        SliverToBoxAdapter(child: SizedBox(height: _bottomScrollPadding(context, hasDock: favoriteApps.isNotEmpty))),
      ],
    );
  }

  double _bottomScrollPadding(BuildContext context, {required bool hasDock}) {
    if (!hasDock) {
      return 64;
    }
    return MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - kToolbarHeight;
  }

  List<Widget> _buildSectionSlivers(
    List<LauncherSection> sections, {
    List<Category> folders = const [],
    bool firstCategoryAlreadyFound = false,
    required bool showAppNames,
    VoidCallback? onFirstSectionFocused,
  }) {
    final List<Widget> slivers = [];
    bool firstCategoryFound = firstCategoryAlreadyFound;
    bool firstBuiltSectionFound = false;
    bool foldersPlaced = folders.isEmpty;

    for (final section in sections) {
      final Key sectionKey = Key(section.id.toString());

      if (section is LauncherSpacer) {
        slivers.add(SliverToBoxAdapter(key: sectionKey, child: SizedBox(height: section.height.toDouble())));
        continue;
      }

      final category = section as Category;
      final filteredApps = category.applications;
      if (filteredApps.isEmpty) continue;

      final bool isFirstSection = !firstCategoryFound;
      if (isFirstSection) firstCategoryFound = true;
      final onAppFocused = !firstBuiltSectionFound
          ? () => _onAppGridFocused(onFirstSectionFocused: onFirstSectionFocused)
          : () => _onAppGridFocused();
      firstBuiltSectionFound = true;

      slivers.add(
        SliverToBoxAdapter(
          child: Selector<SettingsService, bool>(
            selector: (context, service) => service.showCategoryTitles,
            builder: (context, showTitle, _) {
              if (showTitle) {
                return Padding(
                  padding: const EdgeInsets.only(left: 40, bottom: 8, top: 8),
                  child: Text(
                    category.name,
                    style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      shadows: const [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      switch (category.type) {
        case CategoryType.row:
          slivers.add(
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: kLauncherSectionHorizontalPadding,
                  right: kLauncherSectionHorizontalPadding,
                  bottom: 8,
                ),
                child: CategoryRow(
                  key: sectionKey,
                  category: category,
                  applications: filteredApps,
                  isFirstSection: isFirstSection,
                  showTitle: false,
                  onAppFocused: onAppFocused,
                ),
              ),
            ),
          );
          break;
        case CategoryType.folder:
          break;
        case CategoryType.grid:
          final gridContentWidth = MediaQuery.sizeOf(context).width - 2 * kLauncherSectionHorizontalPadding;
          final gridAspectRatio = showAppNames
              ? appCardGridAspectRatio(gridContentWidth, category.columnsCount)
              : kAppCardAspectRatio;
          // The first grid also carries the folder tiles, after its apps.
          final gridFolders = foldersPlaced ? const <Category>[] : folders;
          foldersPlaced = true;
          slivers.add(
            SliverPadding(
              padding: const EdgeInsets.only(
                left: kLauncherSectionHorizontalPadding,
                right: kLauncherSectionHorizontalPadding,
                bottom: 8,
              ),
              sliver: SliverGrid(
                key: sectionKey,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: category.columnsCount,
                  childAspectRatio: gridAspectRatio,
                  mainAxisSpacing: 28, // room for the focused tile's name label
                  crossAxisSpacing: 0,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: filteredApps.length + gridFolders.length,
                  findChildIndexCallback: (Key key) {
                    final valueKey = key as ValueKey<String>;
                    final index = filteredApps.indexWhere((app) => app.packageName == valueKey.value);
                    if (index >= 0) return index;
                    final folderIndex = gridFolders.indexWhere((f) => 'folder-${f.id}' == valueKey.value);
                    return folderIndex >= 0 ? filteredApps.length + folderIndex : null;
                  },
                  (context, index) => index >= filteredApps.length
                      ? _folderTile(gridFolders[index - filteredApps.length], index, category.columnsCount, onAppFocused)
                      : Padding(
                    key: Key(filteredApps[index].packageName),
                    padding: const EdgeInsets.symmetric(
                      horizontal: kAppCardHorizontalPadding,
                      vertical: kAppCardVerticalPadding,
                    ),
                    child: AppCard(
                      category: category,
                      application: filteredApps[index],
                      autofocus: index == 0,
                      handleUpNavigationToSettings: isFirstSection && index < category.columnsCount,
                      enforceAspectRatio: false,
                      // Every grid tile marks the grid focused (blur on); only the first row also scrolls the dock away.
                      onFocused: index < category.columnsCount ? onAppFocused : () => _onAppGridFocused(),
                      ensureVisibleOnFocus: onAppFocused == null || index >= category.columnsCount,
                      onlyScrollWhenNearBottom: true,
                      onMove: (direction) => _onGridMove(context, category, index, direction, filteredApps),
                      onMoveEnd: () => context.read<AppsService>().saveApplicationOrderInCategory(category),
                    ),
                  ),
                ),
              ),
            ),
          );
          break;
      }
    }

    // No grid to sit in: give the folders a grid of their own.
    if (!foldersPlaced) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: kLauncherSectionHorizontalPadding),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: Category.ColumnsCount,
              childAspectRatio: kAppCardAspectRatio,
              mainAxisSpacing: 28,
            ),
            delegate: SliverChildBuilderDelegate(
              childCount: folders.length,
              (context, index) => _folderTile(folders[index], index, Category.ColumnsCount, () => _onAppGridFocused()),
            ),
          ),
        ),
      );
    }

    return slivers;
  }

  Widget _folderTile(Category folder, int index, int columns, VoidCallback onAppFocused) => Padding(
    key: ValueKey('folder-${folder.id}'),
    padding: const EdgeInsets.symmetric(horizontal: kAppCardHorizontalPadding, vertical: kAppCardVerticalPadding),
    // Folders sit after the apps, never in the first row, so they only mark the grid focused.
    child: FolderTile(folder: folder, onFocused: () => _onAppGridFocused()),
  );

  Future<void> _scrollDockToTop() async {
    final targetOffset = _dockTopScrollOffset();
    if (targetOffset == null) {
      return;
    }

    final position = _scrollController.position;
    if ((targetOffset - position.pixels).abs() < 16) {
      return;
    }

    await _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
    );
  }

  double? _dockTopScrollOffset() {
    final dockContext = _dockKey.currentContext;
    final renderObject = dockContext?.findRenderObject();
    if (!_scrollController.hasClients || renderObject == null) {
      return null;
    }

    final viewport = RenderAbstractViewport.of(renderObject);
    final position = _scrollController.position;
    return viewport.getOffsetToReveal(renderObject, 0).offset.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  // TO DO : refractor duplicate _onMove code
  void _onGridMove(
    BuildContext context,
    Category category,
    int index,
    AxisDirection direction,
    List<App> filteredApps,
  ) {
    final currentRow = (index / category.columnsCount).floor();
    final totalRows = ((filteredApps.length - 1) / category.columnsCount).floor();

    int? newIndex;
    switch (direction) {
      case AxisDirection.up:
        if (currentRow > 0) newIndex = index - category.columnsCount;
        break;
      case AxisDirection.right:
        if (index < filteredApps.length - 1) newIndex = index + 1;
        break;
      case AxisDirection.down:
        if (currentRow < totalRows) newIndex = min(index + category.columnsCount, filteredApps.length - 1);
        break;
      case AxisDirection.left:
        if (index > 0) newIndex = index - 1;
        break;
    }

    if (newIndex != null) {
      final appsService = context.read<AppsService>();
      final movingApp = filteredApps[index];
      final realOldIndex = category.applications.indexOf(movingApp);
      final realNewIndex = category.applications.indexOf(filteredApps[newIndex]);
      if (realOldIndex >= 0 && realNewIndex >= 0) {
        appsService.reorderApplication(category, realOldIndex, realNewIndex);
        appsService.setPendingReorderFocus(movingApp.packageName, category.id);
      }
    }
  }

  Widget _dock(
    BuildContext context,
    Category category,
    List<App> apps,
    AppsService appsService, {
    required bool handleUpNavigationToSettings,
  }) {
    final backdropDisabled = context.select<SettingsService, bool>((s) => s.dockBackdropFilterDisabled);
    final darkBackground = context.select<SettingsService, bool>((s) => s.dockDarkBackground);
    final shadowEnabled = context.select<SettingsService, bool>((s) => s.dockShadowEnabled);
    // The cached blur samples the wallpaper only; over Top Shelf art the dock needs a live blur.
    final shelfShowing = context.select<LauncherState, bool>((s) => s.shelfPackage != null);

    final borderRadius = BorderRadius.circular(TvosTokens.dockRadius);

    // tvOS "glass" shelf: translucent fill, thin light stroke, and a brighter sheen along the
    // top edge where light catches it.
    // The backdrop below swaps widget types as focus and scrolling change; the GlobalKey moves the
    // dock across those swaps instead of rebuilding it, which would drop its tiles' focus.
    final content = Container(
      key: _dockContentKey,
      padding: const EdgeInsets.only(top: 8, bottom: 2 + _kDockLabelSpace, left: 12, right: 12),
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.04, 0.35],
          colors: [Color(0x40FFFFFF), Color(0x14FFFFFF), Color(0x00FFFFFF)],
        ),
      ),
      decoration: BoxDecoration(
        color: darkBackground ? Colors.black.withValues(alpha: 0.3) : TvosTokens.glassFill,
        borderRadius: borderRadius,
        border: Border.all(
          color: darkBackground ? Colors.black.withValues(alpha: 0.15) : TvosTokens.glassStroke,
          width: 1,
        ),
      ),
      child: CategoryCleanRow(
        category: category,
        applications: apps,
        isFirstSection: handleUpNavigationToSettings,
        scrollAlignment: 1.0,
        onAppFocused: _onHomeSectionFocused,
        onAppFocusedWithApp: (app) => context.read<LauncherState>().setShelfPackage(app.packageName),
        // Up from the dock goes into the Top Shelf when it has items, otherwise to the status bar.
        onUpPressed: () => context.read<LauncherState>().focusShelf(),
        // The dock never scrolls the page itself; focusing it returns the page to the top.
        ensureVisibleOnFocus: false,
      ),
    );

    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: shadowEnabled
              ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, spreadRadius: 2)]
              : null,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: backdropDisabled
              ? content
              : ValueListenableBuilder<bool>(
                  valueListenable: _dockSettled,
                  child: content,
                  builder: (context, settled, content) {
                    final gridFocused = context.select<LauncherState, bool>((s) => s.appGridFocused);
                    if (!shelfShowing || gridFocused) {
                      // Background is the (blurred) wallpaper: the cheap cached blur matches it.
                      return CachedBlurBackdrop(sigma: 5, child: content!);
                    }
                    if (!settled) {
                      // Mid-scroll over shelf art: a dark tint while the dock moves.
                      return ColoredBox(color: const Color(0x73000000), child: content);
                    }
                    // Frosted glass without a live blur: a 96px copy of the shelf art, stretched to
                    // screen size and aligned with it, reads as heavily blurred and costs almost
                    // nothing. (A live BackdropFilter here added ~12% jank to shelf paging.)
                    return ValueListenableBuilder<Uint8List?>(
                      valueListenable: context.read<LauncherState>().shelfArt,
                      child: content,
                      builder: (context, art, content) {
                        if (art == null) {
                          return ColoredBox(color: const Color(0x73000000), child: content);
                        }
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: _ScreenAligned(
                                child: ShelfImageCrossfade(
                                  image: ResizeImage(MemoryImage(art), width: 96),
                                  filterQuality: FilterQuality.medium,
                                ),
                              ),
                            ),
                            const Positioned.fill(child: ColoredBox(color: Color(0x40000000))),
                            content!,
                          ],
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _wallpaper(BuildContext context, WallpaperService wallpaperService) {
    final screenSize = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final videoFile = wallpaperService.wallpaperVideoFile;
    if (videoFile != null) {
      return SizedBox(
        width: screenSize.width,
        height: screenSize.height,
        child: WallpaperVideoBackground(
          key: ValueKey("background_video_${wallpaperService.wallpaperRevision}"),
          file: videoFile,
        ),
      );
    }
    if (wallpaperService.wallpaper != null) {
      return Image(
        image: ResizeImage(wallpaperService.wallpaper!, height: (screenSize.height * dpr).round()),
        key: ValueKey("background_${wallpaperService.wallpaperRevision}"),
        fit: BoxFit.cover,
        height: screenSize.height,
        width: screenSize.width,
      );
    } else {
      return _CachedGradientBackground(key: const Key("background"), gradient: wallpaperService.gradient.gradient);
    }
  }

  Widget _emptyState(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(localizations.loading, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

/// Lays its child out at full-screen size and paints it shifted so it lines up with the screen,
/// whatever box it sits in: the dock uses this to show the part of the Top Shelf art behind it.
class _ScreenAligned extends SingleChildRenderObjectWidget {
  const _ScreenAligned({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderScreenAligned(MediaQuery.sizeOf(context));

  @override
  void updateRenderObject(BuildContext context, _RenderScreenAligned renderObject) {
    renderObject.screenSize = MediaQuery.sizeOf(context);
  }
}

class _RenderScreenAligned extends RenderProxyBox {
  Size _screenSize;

  _RenderScreenAligned(this._screenSize);

  set screenSize(Size value) {
    if (value != _screenSize) {
      _screenSize = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    child?.layout(BoxConstraints.tight(_screenSize));
    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    context.paintChild(child, offset - localToGlobal(Offset.zero));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => false;
}

/// Renders a [Gradient] once into a rasterized [ui.Image] and blits it as a
/// texture instead of evaluating the gradient shader every frame.
///
/// On low-end GPUs (e.g. Android TV sticks) a full-screen live gradient is
/// noticeably more expensive to raster than a cached texture, so this keeps the
/// background as cheap as a static image wallpaper.
class _CachedGradientBackground extends StatefulWidget {
  final Gradient gradient;

  const _CachedGradientBackground({super.key, required this.gradient});

  @override
  State<_CachedGradientBackground> createState() => _CachedGradientBackgroundState();
}

class _CachedGradientBackgroundState extends State<_CachedGradientBackground> {
  ui.Image? _image;
  Size _renderedSize = Size.zero;
  Gradient? _renderedGradient;
  bool _rendering = false;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _render(Size size) async {
    if (_rendering) {
      return;
    }
    _rendering = true;
    final recorder = ui.PictureRecorder();
    final rect = Offset.zero & size;
    Canvas(recorder).drawRect(rect, Paint()..shader = widget.gradient.createShader(rect));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.round(), size.height.round());
    picture.dispose();
    _rendering = false;
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _renderedSize = size;
      _renderedGradient = widget.gradient;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final needsRender = size != _renderedSize || widget.gradient != _renderedGradient;
        if (needsRender && size.width > 0 && size.height > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (size != _renderedSize || widget.gradient != _renderedGradient)) {
              _render(size);
            }
          });
        }
        final image = _image;
        if (image != null && !needsRender) {
          return RawImage(image: image, width: size.width, height: size.height, fit: BoxFit.fill);
        }
        // First frame (and while re-rendering): paint the gradient live once to avoid a flash.
        return DecoratedBox(decoration: BoxDecoration(gradient: widget.gradient));
      },
    );
  }
}
