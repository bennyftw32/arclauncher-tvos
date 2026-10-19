# Arc Launcher → tvOS redesign plan

Fork: `bennyftw32/arclauncher-tvos` (upstream `meddouribadis/arclauncher`, GPL-3.0, Flutter 3.41.9).
Target device: Xiaomi TV Box S Gen 3 (Amlogic, 2 GB RAM, Android TV 14, 4K60 output, Dolby Vision), driven by D-pad remote.

Why this base: AT4K (the launcher on the box today) is closed source and can't be forked. Arc is the
open-source launcher already aimed at an Apple TV look — it has a dock, blur, Watch Next, folders
(categories) and a move mode, so most of the work is restyling and re-wiring focus, not new plumbing.

## What "looks like Apple TV" means here

The reference is tvOS 26 on a 1080p canvas (Flutter renders at 1920×1080 logical on this box).

| tvOS element | What it does | Arc today |
|---|---|---|
| **Top Shelf** | Upper ~⅔ of the screen is full-bleed art for whichever **dock** app is focused (its Up Next / featured items). Changes with focus, crossfades. | `WatchNextRow` above the dock: a carousel of cards, not full-bleed, not tied to the focused app |
| **Dock** | One row of 5 apps on a translucent "glass" shelf near the vertical middle. Edges catch light (Liquid Glass). | `_dock()` in `flauncher.dart`: blurred rounded container, 6 apps, bottom of screen |
| **App grid** | Below the dock, 5 per row, no labels. Pressing down from the dock scrolls the page up and the Top Shelf area blurs/dims. | Grid sections with optional labels; blur fades in on grid focus (`CachedBlurLayer`) — close |
| **Icons** | 5:3 rounded rectangles (~400×240 @1x), no border. **Focus** = scale up (~+10%), deeper shadow, parallax tilt + moving specular glare; app name appears *under the focused icon only*. | 16:9 cards, accent-colour outline, scale 1.07, optional names under every icon |
| **No status bar** | Home screen has no clock / Wi-Fi / settings icons. Time lives in Control Center. | `FocusAwareAppBar` with settings, Wi-Fi, clock |
| **Control Center** | Hold Home/TV → right-side glass panel: time, sleep, profiles, audio output, Wi-Fi, accessibility. | None |
| **Wiggle mode** | Long-press an app → icons jiggle, move with D-pad, Play/Pause opens options (delete, move to folder). | Move mode with arrow overlays |
| **Folders** | Apps grouped into a folder tile showing mini icons; opens as an overlay grid. | Categories as rows/grids (no folder tile) |
| **Screensaver** | Aerial videos. | Built-in clock screensaver |
| **Typography** | SF Pro; large bold titles, light secondary text. | Material default (Roboto) |
| **Sounds** | Soft tick on focus move, click on select. | None |

## Constraints (read before building)

- **No Apple assets.** SF Pro's license only allows use on Apple platforms, and Apple icons/wallpapers/sounds
  are copyrighted. Use **Inter** (SIL OFL) for type, draw our own glyphs, and synthesize our own sounds.
  Aerial screensavers come from the user-installed Aerial Views app (it streams Apple's videos itself),
  so the launcher just hands off to the system screensaver.
- **GPL-3.0.** Keep `LICENSE`, the FLauncher/LtvLauncher/Arc attribution, and keep the fork public. Change
  `applicationId` (`com.omeda.arc` → e.g. `com.bennyftw32.arctv`) so it installs alongside upstream.
- **Performance budget.** The box is a 2 GB Amlogic stick-class SoC. Full-screen blur is the expensive part;
  Arc already caches blur (`cached_blur_backdrop.dart`). Every phase must hold 60 fps on the box
  (`adb shell dumpsys gfxinfo com.bennyftw32.arctv` → janky frames < 5%).
- **Home button.** On Google TV the Home key goes to the system HOME role. Setting the fork as the HOME role
  (`cmd role add-role-holder android.app.role.HOME …`) is enough for Home → launcher; *long-press* Home for
  Control Center needs an AccessibilityService (same approach AT4K uses).

## Phases

Each phase ends with: build → `adb install` on the Xiaomi (192.168.1.24) → screenshot script → compare
against the tvOS reference shots in `docs/tvos-ref/` (to be collected in Phase 0).

### Phase 0 — Toolchain and baseline
- Install FVM + Flutter 3.41.9 (per `.fvmrc`), Android SDK 35 + build-tools, JDK 17 (already on this PC).
- `fvm flutter build apk --debug --target-platform android-arm` (box is armeabi-v7a only).
- Change `applicationId`/`namespace` and app label to "Arc TV"; keep the debug suffix.
- `tools/shot.ps1`: adb screencap of home, dock-focused, grid-focused, settings → `docs/shots/<phase>/`.
- Collect reference screenshots of tvOS 26 home (dock focused, grid focused, Control Center, wiggle mode)
  into `docs/tvos-ref/` for side-by-side review only (not shipped).
- **Done when:** the stock fork runs on the box as HOME and baseline shots are saved.

### Phase 1 — Design tokens and chrome removal
- New `lib/theme/tvos_tokens.dart`: colours (dark: `#0B0B0D` base, glass fill `white @ 12%`, glass stroke
  `white @ 22%`), radii (icon 12, dock 32, panels 28), spacing (90 px side safe area, 60 px top),
  focus scale 1.10, shadow tiers, motion curves (`Curves.easeOutCubic` 200 ms focus, 350 ms shelf crossfade).
- Bundle Inter (Regular/Medium/Semibold/Bold) under `assets/fonts/`, wire into `flauncher_app.dart` `ThemeData`.
- `focus_aware_app_bar.dart`: add a "tvOS mode" (default on) that renders nothing; settings is reached
  from Control Center (Phase 6) or a long-press on the dock's Settings app.
- `settings_service.dart`: new defaults — names under icons off, category titles off, focus borders off,
  highlight animation off, built-in screensaver off.
- **Done when:** home shows only wallpaper + dock + grid, in Inter.

### Phase 2 — tvOS icon tiles (`lib/widgets/app_card.dart`)
- Aspect ratio 16:9 → **5:3** (`kAppCardAspectRatio`), corner radius from tokens, remove `_HighlightOutline`
  and the dimming overlay.
- Focus: scale 1.10, shadow grows (blur 10→30, y-offset 6→18), name label fades in under the focused
  tile only (replace `_AppNameLabel` always-on logic).
- **Parallax + glare:** new `lib/widgets/parallax_tile.dart`. On focus, and on each D-pad press while
  focused, apply a short tilt (`Matrix4..setEntry(3,2,0.0015)..rotateX/Y` up to ~4°) toward the pressed
  direction that springs back, plus a radial white gradient "glare" that slides across. Banner apps get
  it on the whole image; icon-only apps get the icon centred on a generated background
  (dominant colour from the icon via `palette_generator`, instead of today's icon + text row).
- Press: quick scale-down 0.95 then launch (keep existing `_clicked` path, retune).
- **Done when:** focusing across the dock looks and feels like tvOS in a 10-second screen recording.

### Phase 3 — Top Shelf (`lib/widgets/top_shelf.dart`, replaces `WatchNextRow` on home)
- Layout: shelf fills the area above the dock (≈ 0–620 px of 1080), full-bleed image, bottom gradient into
  the dock, title + subtitle bottom-left in Inter Bold/Medium, page dots if the app has several items.
- Data: when a **dock** app gains focus, look up `WatchNextService` items for that package; Left/Right
  while the shelf is focused pages through them, Select launches via `launchWatchNextItem`. Fallback when
  the app has none: the app's banner, scaled and blurred, or the wallpaper.
- Extend `MainActivity.java` `getWatchNextItems` to also read `TvContract.PreviewPrograms` for the focused
  package's channels (what Netflix/YouTube/Disney+ publish for "featured" rows) — that is closest to
  Apple's Top Shelf content. Permission: `com.android.providers.tv.permission.READ_EPG_DATA`
  (grant via `pm grant` once; document it).
- Crossfade 350 ms between apps; debounce 150 ms so fast scrolling across the dock doesn't thrash images.
- **Done when:** moving across Netflix → YouTube → Disney+ in the dock swaps the shelf like Apple TV.

### Phase 4 — Dock, grid and scrolling (`lib/flauncher.dart`)
- Dock: 5 apps (`Category.ColumnsCount` for Favorites = 5), positioned with its top at ~58% of screen
  height, full-width glass shelf: blur sigma 30 + `white @ 12%` fill + 1 px top highlight gradient
  ("sparkle edge"), no drop shadow.
- Grid: 5 columns, 40 px row gap, no titles. Moving down from the dock animates the scroll so the dock
  rides to the top edge and the shelf area blurs + dims (reuse `CachedBlurLayer`, tune sigma 25, 40% black).
- Folders: categories with `type == grid` and a "folder" flag render as a single tile with a 3×3 mini-icon
  preview; Select opens a centred glass overlay grid (new `lib/widgets/folder_overlay.dart`).
- **Done when:** a full pass dock → grid → folder → back matches the reference shots.

### Phase 5 — Wiggle mode, menus, sounds
- Replace move-mode arrows with a jiggle (±1.5° rotation, 120 ms, random phase per tile) on all tiles;
  focused tile lifts; Select drops it; Play/Pause or Menu opens an options sheet
  (Move to folder / New folder / Hide / Uninstall) styled as a tvOS action sheet.
- Long-press context menu (`application_info_panel.dart`) restyled as a centred glass sheet.
- Focus tick + select click: tiny bundled `.ogg` files we synthesise ourselves, played via
  `SystemSound`-style low-latency player; setting to turn off.
- **Done when:** reordering and foldering apps needs no help text.

### Phase 6 — Control Center and Home button
- New `ArcAccessibilityService.java`: catches long-press `KEYCODE_HOME` (and `KEYCODE_TV` where present)
  and broadcasts to the launcher; short press untouched. User enables it once (or `settings put secure
  enabled_accessibility_services …` over adb).
- `lib/widgets/control_center.dart`: right-side glass column — time/date, Sleep (calls `goToSleep` via
  `input keyevent KEYCODE_SLEEP` equivalent), Wi-Fi (existing `openWifiSettings`), Audio output,
  Settings, Screensaver now (`startAmbientMode`).
- **Done when:** holding Home anywhere opens Control Center over the current app.

### Phase 7 — Screensaver and polish
- Default to the **system** screensaver (Aerial Views) and remove the internal idle timer from
  defaults; keep the clock screensaver as an option.
- Light/Dark appearance follows time of day (existing time-based wallpaper logic).
- Performance pass on the box: profile build, `gfxinfo`, trim blur radii/repaint boundaries until < 5% jank.

### Phase 8 — Ship
- Release signing, versioning `1.0.0-tvos`, GitHub Actions build (workflow already in `.github/`),
  install on both boxes (Xiaomi 192.168.1.24, onn 192.168.1.31), set HOME role, disable AT4K.
- README section crediting upstream and stating it is an independent project, not affiliated with Apple.

## Files touched (map)

| Area | Files |
|---|---|
| Theme / fonts | `lib/flauncher_app.dart`, new `lib/theme/tvos_tokens.dart`, `assets/fonts/`, `pubspec.yaml` |
| Chrome | `lib/widgets/focus_aware_app_bar.dart`, `lib/providers/settings_service.dart` |
| Tiles | `lib/widgets/app_card.dart`, new `lib/widgets/parallax_tile.dart` |
| Top Shelf | new `lib/widgets/top_shelf.dart`, `lib/providers/watch_next_service.dart`, `android/.../MainActivity.java` |
| Layout | `lib/flauncher.dart`, `lib/widgets/category_clean_row.dart`, `lib/custom_traversal_policy.dart` |
| Folders | `lib/models/category.dart`, `lib/database.dart` (schema bump + migration), new `lib/widgets/folder_overlay.dart` |
| Wiggle / menus | `lib/widgets/app_card.dart`, `lib/widgets/application_info_panel.dart` |
| Control Center | new `android/.../ArcAccessibilityService.java`, `AndroidManifest.xml`, new `lib/widgets/control_center.dart`, `lib/flauncher_channel.dart` |
| IDs / release | `android/app/build.gradle`, `README.md`, `.github/workflows/` |

## Risks

- **Top Shelf data** depends on apps publishing PreviewPrograms; some (e.g. Netflix) restrict them to
  the system launcher. Fallback art keeps it looking right either way.
- **Blur cost** on the Amlogic GPU — the cached-blur approach must stay; live blur behind a moving shelf
  may need a downscaled (¼ res) blur texture.
- **Long-press Home** behaviour varies by firmware; if the accessibility service can't see it, fall back to
  long-press Back or the Xiaomi remote's dedicated button.
- **Upstream churn** — Arc ships often (1.0.8 → 1.0.10 in a month). Keep changes in new files where
  possible and rebase on `upstream/main` per phase.
