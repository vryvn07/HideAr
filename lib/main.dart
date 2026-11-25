import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'overlay/overlay_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/protection_active_screen.dart';
import 'services/app_exit.dart';
import 'services/autostart.dart';
import 'services/camera_selection.dart';
import 'services/settings_service.dart';
import 'theme/tokens.dart';

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Present when Windows started us at sign-in via the Run key.
  final bool launchedAtSignIn = args.contains(kAutostartFlag);
  await SettingsService.instance.load();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    windowManager.addListener(_WindowsTrayListener());

    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: W.panel,
        minimumSize: W.minimum,
        center: true,
        backgroundColor: C.beige,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      ),
      () async {
        if (launchedAtSignIn) return;
        await windowManager.show();
        await windowManager.focus();
      },
    );
    await windowManager.setPreventClose(false);

    // HideAr is an unzip-anywhere folder; if it was moved since autostart
    // was enabled, point the Run entry at the new location.
    await AutostartService().repairIfMoved();
  }

  runApp(HideArApp(launchedAtSignIn: launchedAtSignIn));
}

class _WindowsTrayListener extends WindowListener {
  @override
  void onWindowMinimize() => windowManager.hide();
}

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: OverlayScreen()),
  );
}

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------

class HideArApp extends StatelessWidget {
  const HideArApp({super.key, this.launchedAtSignIn = false});

  final bool launchedAtSignIn;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HideAr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: C.espresso,
          brightness: Brightness.light,
        ).copyWith(surface: C.beige, onSurface: C.espresso),
        scaffoldBackgroundColor: C.beige,
        splashFactory: NoSplash.splashFactory,
        useMaterial3: true,
      ),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mq = MediaQuery.of(context);
        final double scale = mq.textScaler.scale(14) / 14;
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(scale.clamp(1.0, 1.35)),
          ),
          child: child!,
        );
      },
      home: HideArHome(launchedAtSignIn: launchedAtSignIn),
    );
  }
}

// ---------------------------------------------------------------------------
// Home screen
// ---------------------------------------------------------------------------

class HideArHome extends StatefulWidget {
  const HideArHome({super.key, this.launchedAtSignIn = false});

  /// When true, go straight into protection once the camera checks out.
  final bool launchedAtSignIn;

  @override
  State<HideArHome> createState() => _HideArHomeState();
}

class _HideArHomeState extends State<HideArHome> with tray.TrayListener {
  bool _checking = true;
  String? _error;
  bool _canOpenSettings = false;
  int _selectedTab = 0;

  double _sensitivity = SettingsService.instance.sensitivity;
  bool _detectShoulderSurfers = SettingsService.instance.detectShoulderSurfers;
  String? _cameraName;
  bool _cameraIsVirtual = false;
  bool _showCameraPreview = SettingsService.instance.showCameraPreview;
  bool _startWithWindows = false;
  bool _autostartHandled = false;
  final AutostartService _autostart = AutostartService();

  String get _cameraLabel => _cameraName ?? 'Detected';

  Future<void> _refreshAutostart() async {
    final bool on = await _autostart.isEnabled();
    if (mounted) setState(() => _startWithWindows = on);
  }

  @override
  void initState() {
    super.initState();
    _checkCamera();
    if (Platform.isWindows) {
      tray.trayManager.addListener(this);
      _initWindowsTray();
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      tray.trayManager.removeListener(this);
      tray.trayManager.destroy();
    }
    super.dispose();
  }

  // ── Tray ──────────────────────────────────────────────────────────────────

  Future<void> _initWindowsTray() async {
    try {
      final byteData = await rootBundle.load('assets/tray_icon.ico');
      final dir = await getTemporaryDirectory();
      final icoPath = path.join(dir.path, 'hidear_tray.ico');
      await File(icoPath).writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
      );
      await tray.trayManager.setIcon(icoPath);
      await tray.trayManager.setToolTip('HideAr');
      await tray.trayManager.setContextMenu(
        tray.Menu(
          items: [
            tray.MenuItem(key: 'show', label: 'Show HideAr'),
            tray.MenuItem(key: 'hide', label: 'Hide to tray'),
            tray.MenuItem.separator(),
            tray.MenuItem(key: 'exit', label: 'Exit HideAr'),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Tray init: $e');
    }
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    tray.trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem item) {
    switch (item.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
      case 'hide':
        windowManager.hide();
      case 'exit':
        exitHideAr();
    }
  }

  // ── Camera check ──────────────────────────────────────────────────────────

  Future<void> _checkCamera() async {
    setState(() {
      _checking = true;
      _error = null;
      _canOpenSettings = false;
    });
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          if (mounted) {
            setState(() {
              _checking = false;
              _canOpenSettings = status.isPermanentlyDenied;
              _error =
                  status.isPermanentlyDenied
                      ? 'Camera access was permanently denied. Enable it in Settings.'
                      : 'Camera access is required to detect gaze.';
            });
          }
          return;
        }
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _checking = false;
            _error = 'No camera found on this device.';
          });
        }
        return;
      }
      final CameraChoice? choice = chooseCamera(
        cameras
            .map(
              (CameraDescription c) => CameraOption.fromRaw(
                c.name,
                isFront: c.lensDirection == CameraLensDirection.front,
              ),
            )
            .toList(),
      );

      if (mounted) {
        setState(() {
          _checking = false;
          final String name = choice?.option.name.trim() ?? '';
          _cameraName = name.isEmpty ? null : name;
          _cameraIsVirtual = choice?.isVirtual ?? false;
        });
        if (widget.launchedAtSignIn && !_autostartHandled) {
          _autostartHandled = true;
          _goToProtection();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checking = false;
          _error = e.toString();
        });
      }
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _goToProtection() {
    if (!Platform.isAndroid) {
      Navigator.of(context).push(_route(const ProtectionActiveScreen()));
      return;
    }
    _startAndroidOverlay();
  }

  Future<void> _startAndroidOverlay() async {
    try {
      // ignore: unnecessary_null_aware_operator
      bool granted = (await FlutterOverlayWindow.isPermissionGranted()) == true;
      if (!granted) {
        // ignore: unnecessary_null_aware_operator
        granted = (await FlutterOverlayWindow.requestPermission()) == true;
      }
      if (!granted || !mounted) return;
      await FlutterOverlayWindow.showOverlay(
        height: WindowSize.fullCover,
        width: WindowSize.matchParent,
        flag: OverlayFlag.defaultFlag,
        overlayTitle: 'HideAr',
        overlayContent: 'Privacy protection active',
      );
      if (!mounted) return;
      Navigator.of(context).push(_route(const ProtectionActiveScreen()));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Overlay error: $e')));
      }
    }
  }

  void _goToPrivacyScreen() {
    Navigator.of(context).push(_route(const PrivacyScreen()));
  }

  static PageRoute _route(Widget page) =>
      MaterialPageRoute(builder: (_) => page);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final String? headerBadge =
        _checking ? 'SCAN' : (_error != null ? 'ALERT' : 'READY');
    final Color? badgeDot =
        _checking ? C.cocoa : (_error != null ? C.caramel : C.olive);

    return Scaffold(
      backgroundColor: C.beige,
      body: Column(
        children: [
          if (Platform.isWindows)
            HideArHeader(
              title: 'HideAr',
              badgeText: headerBadge,
              badgeDotColor: badgeDot,
              onMinimise: () => windowManager.hide(),
              onClose: exitHideAr,
              onDragStart: () => windowManager.startDragging(),
            ),
          Expanded(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(S.x4),
                child: _buildBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_checking) return _buildChecking();
    if (_error != null) return _buildError();
    return _buildDashboard();
  }

  // -- States ---------------------------------------------------------------

  Widget _buildChecking() {
    return SurfaceCard(
      padding: const EdgeInsets.all(S.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: C.espresso,
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: const Icon(
                  Icons.videocam_outlined,
                  color: C.beige,
                  size: 22,
                ),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Initialising Sensor', style: T.heading),
                    const SizedBox(height: 2),
                    Text('Checking local camera availability', style: T.body),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x5),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: const LinearProgressIndicator(
              minHeight: 6,
              color: C.espresso,
              backgroundColor: C.sandDeep,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfaceCard(
          color: C.caramelSoft,
          borderColor: C.caramel,
          padding: const EdgeInsets.all(S.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: C.caramel,
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                    child: const Icon(
                      Icons.videocam_off_rounded,
                      color: C.beige,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(
                      'Sensor Unavailable',
                      style: T.heading.copyWith(color: C.espresso),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x3),
              Text(_error!, style: T.body),
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        ActionPillButton(
          label: 'Try Again',
          primary: true,
          icon: Icons.refresh_rounded,
          onPressed: _checkCamera,
        ),
        if (_canOpenSettings) ...[
          const SizedBox(height: S.x2),
          ActionPillButton(
            label: 'Open System Settings',
            tonal: true,
            icon: Icons.settings_outlined,
            onPressed: () async {
              await openAppSettings();
              if (mounted) _checkCamera();
            },
          ),
        ],
      ],
    );
  }

  // -- Dashboard ------------------------------------------------------------

  Widget _buildDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedTabs(
          labels: const <String>['Overview', 'Preferences'],
          selectedIndex: _selectedTab,
          onChanged: (int index) {
            setState(() => _selectedTab = index);
            if (index == 1) _refreshAutostart();
          },
        ),
        const SizedBox(height: S.x4),
        if (_selectedTab == 0) _buildOverviewTab() else _buildPreferencesTab(),
      ],
    );
  }

  Widget _buildOverviewTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfaceCard(
          color: C.espresso,
          borderColor: C.roast,
          padding: const EdgeInsets.all(S.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: S.x2 + 2,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: C.roast,
                      borderRadius: BorderRadius.circular(R.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: C.olive,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'LOCAL ONLY • OFFLINE',
                          style: T.caption.copyWith(
                            color: C.beige,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x3),
              Text(
                'Gaze Privacy Shield',
                style: T.hero.copyWith(color: C.beige),
              ),
              const SizedBox(height: S.x2),
              Text(
                'Conceals your display the moment you turn away or when a '
                'second person appears behind you.',
                style: T.body.copyWith(color: C.sandDeep),
              ),
            ],
          ),
        ),
        const SizedBox(height: S.x3),
        Row(
          children: [
            Expanded(
              child: BentoTile(
                icon: Icons.videocam_rounded,
                label: 'Sensor',
                value: _cameraLabel,
              ),
            ),
            const SizedBox(width: S.x2 + 2),
            Expanded(
              child: BentoTile(
                icon: Icons.tune_rounded,
                label: 'Tolerance',
                value: _sensitivityLabel(_sensitivity),
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x2 + 2),
        Row(
          children: [
            Expanded(
              child: BentoTile(
                icon: Icons.group_outlined,
                label: 'Bystander',
                value: _detectShoulderSurfers ? 'Active' : 'Paused',
                valueColor: _detectShoulderSurfers ? C.olive : C.cocoa,
                toneColor: _detectShoulderSurfers ? C.oliveSoft : C.sandDeep,
              ),
            ),
            const SizedBox(width: S.x2 + 2),
            const Expanded(
              child: BentoTile(
                icon: Icons.cloud_off_rounded,
                label: 'Network',
                value: 'None',
                valueColor: C.olive,
                toneColor: C.oliveSoft,
              ),
            ),
          ],
        ),
        if (_cameraIsVirtual) ...[
          const SizedBox(height: S.x3),
          _buildVirtualCameraWarning(),
        ],
        const SizedBox(height: S.x4),
        ActionPillButton(
          label: Platform.isAndroid ? 'Enable Overlay' : 'Activate Shield',
          primary: true,
          icon: Icons.shield_rounded,
          onPressed: _goToProtection,
        ),
        const SizedBox(height: S.x2),
        ActionPillButton(
          label: 'Preview Blur Mode',
          tonal: true,
          icon: Icons.blur_on_rounded,
          onPressed: _goToPrivacyScreen,
        ),
      ],
    );
  }

  Widget _buildVirtualCameraWarning() {
    return SurfaceCard(
      color: C.caramelSoft,
      borderColor: C.caramel,
      padding: const EdgeInsets.all(S.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: C.caramel,
              ),
              const SizedBox(width: S.x2),
              Text(
                'Virtual Camera Detected',
                style: T.heading.copyWith(fontSize: 13.5, color: C.caramel),
              ),
            ],
          ),
          const SizedBox(height: S.x2),
          Text(
            'This camera applies effects before HideAr sees a frame. '
            'Background blur can hide bystanders from detection; use a '
            'physical webcam for full protection.',
            style: T.body,
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(S.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Gaze Tolerance', style: T.heading)),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: S.x2 + 2,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: C.espresso,
                      borderRadius: BorderRadius.circular(R.pill),
                    ),
                    child: Text(
                      '${_sensitivityLabel(_sensitivity)} • ${(_sensitivity * 100).round()}%',
                      style: T.caption.copyWith(color: C.beige, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x2),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: C.espresso,
                  inactiveTrackColor: C.sandDeep,
                  thumbColor: C.caramel,
                  overlayColor: C.caramel.withValues(alpha: 0.14),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  tickMarkShape: SliderTickMarkShape.noTickMark,
                ),
                child: Slider(
                  value: _sensitivity,
                  divisions: 4,
                  onChanged: (double v) => setState(() => _sensitivity = v),
                  onChangeEnd: SettingsService.instance.setSensitivity,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Lenient', style: T.caption),
                  Text('Strict', style: T.caption),
                ],
              ),
              const SizedBox(height: S.x2 + 2),
              Text(_sensitivityDescription(_sensitivity), style: T.body),
            ],
          ),
        ),
        const SizedBox(height: S.x3),
        SurfaceCard(
          padding: const EdgeInsets.all(S.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Privacy Behaviour', style: T.heading),
              const SizedBox(height: S.x3),
              _buildToggleRow(
                title: 'Second-Face Shield',
                subtitle: 'Veil the display if a bystander is seen',
                value: _detectShoulderSurfers,
                onChanged: (bool v) {
                  setState(() => _detectShoulderSurfers = v);
                  SettingsService.instance.setDetectShoulderSurfers(v);
                },
              ),
              const Divider(color: C.border, height: 22),
              _buildToggleRow(
                title: 'Sensor Preview',
                subtitle: 'Show live camera thumbnail while active',
                value: _showCameraPreview,
                onChanged: (bool v) {
                  setState(() => _showCameraPreview = v);
                  SettingsService.instance.setShowCameraPreview(v);
                },
              ),
              if (Platform.isWindows) ...[
                const Divider(color: C.border, height: 22),
                _buildToggleRow(
                  title: 'Launch at Sign-In',
                  subtitle: 'Start protected from the tray after login',
                  value: _startWithWindows,
                  onChanged: (bool v) async {
                    final ScaffoldMessengerState messenger =
                        ScaffoldMessenger.of(context);
                    setState(() => _startWithWindows = v);
                    final bool ok = await _autostart.setEnabled(v);
                    if (!mounted) return;
                    await _refreshAutostart();
                    if (!ok) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Could not change the startup entry.'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: T.value),
              const SizedBox(height: 2),
              Text(subtitle, style: T.body.copyWith(fontSize: 11.5)),
            ],
          ),
        ),
        const SizedBox(width: S.x2),
        Switch(
          value: value,
          activeColor: C.beige,
          activeTrackColor: C.espresso,
          inactiveThumbColor: C.cocoa,
          inactiveTrackColor: C.sandDeep,
          onChanged: onChanged,
        ),
      ],
    );
  }

  String _sensitivityLabel(double v) {
    if (v <= 0.1) return 'Very lenient';
    if (v <= 0.35) return 'Lenient';
    if (v <= 0.65) return 'Medium';
    if (v <= 0.85) return 'Strict';
    return 'Very strict';
  }

  String _sensitivityDescription(double v) {
    if (v <= 0.35) {
      return 'Allows wider head movement before hiding. Suits active desks.';
    }
    if (v <= 0.65) {
      return 'Balanced response that tolerates slight posture shifts.';
    }
    return 'Responds quickly to small turns. Best for sensitive workspaces.';
  }
}
