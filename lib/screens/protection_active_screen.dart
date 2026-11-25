// Protection screen: the camera runs while this route is mounted. On Windows
// the window expands to a fullscreen espresso veil when the user looks away; on
// Android (experimental) it notifies the separate overlay process instead.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../services/app_exit.dart';
import '../services/camera_effects.dart';
import '../services/camera_gaze_service.dart';
import '../services/display_geometry.dart';
import '../services/gaze_detector_service.dart';
import '../services/head_pose_estimator.dart';
import '../services/settings_service.dart';
import '../theme/tokens.dart';

class ProtectionActiveScreen extends StatefulWidget {
  const ProtectionActiveScreen({super.key});

  @override
  State<ProtectionActiveScreen> createState() => _ProtectionActiveScreenState();
}

class _ProtectionActiveScreenState extends State<ProtectionActiveScreen>
    with WindowListener {
  late final GazeDetectorService _gazeDetector;
  late final CameraGazeService _cameraGazeService;

  bool _isStarting = true;
  String? _error;

  bool _overlayActive = false;
  bool _hiddenBeforeBlackout = false;
  Timer? _windowDebounce;
  Future<void> _windowOp = Future<void>.value();
  bool _lastNotifiedVisible = false;
  Timer? _watchdog;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final SettingsService settings = SettingsService.instance;
    _gazeDetector = GazeDetectorService(
      sensitivity: settings.sensitivity,
      detectShoulderSurfers: settings.detectShoulderSurfers,
    );
    _cameraGazeService = CameraGazeService(
      gazeDetector: _gazeDetector,
      onGazeStateChanged: _onGazeChanged,
      onError: (msg) {
        if (!mounted) return;
        setState(() {
          _isStarting = false;
          _error = msg;
        });
        if (Platform.isWindows) _applyWindowMode();
      },
    );
    _cameraGazeService.keepPreviewFrame = settings.showCameraPreview;
    if (Platform.isWindows) {
      windowManager.addListener(this);
      _initWindowsMode();
    }
    _startCamera();
    _watchdog = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _checkForStateDrift(),
    );
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _windowDebounce?.cancel();
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      _restoreWindowSize();
    }
    _cameraGazeService.stop();
    super.dispose();
  }

  void _checkForStateDrift() {
    if (!mounted) return;
    if (_gazeDetector.isScreenVisible != _lastNotifiedVisible) {
      _onGazeChanged();
    } else {
      setState(() {});
    }
  }

  // ── Windows window management ─────────────────────────────────────────────

  Future<void> _initWindowsMode() async {
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(W.panel);
    await windowManager.center();
  }

  Future<void> _restoreWindowSize() async {
    try {
      await windowManager.setFullScreen(false);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setSize(W.panel);
      await windowManager.center();
    } catch (_) {}
  }

  bool get _blackoutWanted =>
      !_isStarting && _error == null && !_gazeDetector.isScreenVisible;

  @override
  void onWindowBlur() {
    if (!Platform.isWindows || !mounted) return;
    if (!_blackoutWanted) return;
    _enqueueWindowOp(() async {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  void _scheduleWindowUpdate() {
    _windowDebounce?.cancel();
    _windowDebounce = Timer(
      const Duration(milliseconds: 120),
      _applyWindowMode,
    );
  }

  void _enqueueWindowOp(Future<void> Function() op) {
    _windowOp = _windowOp.then((_) async {
      if (!mounted) return;
      try {
        await op();
      } catch (e) {
        debugPrint('HideAr window op failed: $e');
      }
    });
  }

  Future<void> _coverAllDisplays() async {
    List<Display> displays = const <Display>[];
    try {
      displays = await screenRetriever.getAllDisplays();
    } catch (e) {
      debugPrint('HideAr: could not enumerate displays: $e');
    }

    if (displays.length < 2) {
      await windowManager.setFullScreen(true);
      return;
    }

    final CoverRect? cover = computeCoverRect(
      displays.map((Display d) {
        final Offset origin = d.visiblePosition ?? Offset.zero;
        return DisplayBounds(
          left: origin.dx,
          top: origin.dy,
          width: d.size.width,
          height: d.size.height,
          scaleFactor: (d.scaleFactor ?? 1).toDouble(),
        );
      }).toList(),
      windowScaleFactor: windowManager.getDevicePixelRatio(),
    );

    if (cover == null || cover.width < 200 || cover.height < 200) {
      debugPrint('HideAr: display union looked wrong, using fullscreen');
      await windowManager.setFullScreen(true);
      return;
    }

    await windowManager.setFullScreen(false);
    await windowManager.setBounds(
      Rect.fromLTWH(cover.left, cover.top, cover.width, cover.height),
    );
  }

  void _applyWindowMode() {
    if (!mounted || !Platform.isWindows) return;
    _enqueueWindowOp(() async {
      final bool wantBlackout = _blackoutWanted;
      if (wantBlackout && !_overlayActive) {
        _overlayActive = true;
        _hiddenBeforeBlackout = !(await windowManager.isVisible());
        await windowManager.show();
        await _coverAllDisplays();
        await windowManager.setAlwaysOnTop(true);
        await windowManager.focus();
      } else if (!wantBlackout && _overlayActive) {
        _overlayActive = false;
        await windowManager.setFullScreen(false);
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setSize(W.panel);
        await windowManager.center();
        if (_hiddenBeforeBlackout) {
          _hiddenBeforeBlackout = false;
          await windowManager.hide();
        }
      }
    });
  }

  // ── Gaze callback ─────────────────────────────────────────────────────────

  void _onGazeChanged() {
    if (!mounted) return;
    setState(() {});

    final bool isVisible = _gazeDetector.isScreenVisible;
    _lastNotifiedVisible = isVisible;

    if (Platform.isAndroid) {
      try {
        FlutterOverlayWindow.shareData(isVisible ? 'looking' : 'away');
      } catch (_) {}
    }
    if (Platform.isWindows) {
      _scheduleWindowUpdate();
    }
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _startCamera() async {
    setState(() {
      _isStarting = true;
      _error = null;
    });
    try {
      await _cameraGazeService.start();
      if (!mounted) return;
      setState(() => _isStarting = false);
      _lastNotifiedVisible = _gazeDetector.isScreenVisible;
      if (Platform.isAndroid) {
        try {
          FlutterOverlayWindow.shareData(
            _gazeDetector.isScreenVisible ? 'looking' : 'away',
          );
        } catch (_) {}
      }
      if (Platform.isWindows) _applyWindowMode();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isStarting = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _stopProtection() async {
    await _cameraGazeService.stop();
    if (Platform.isWindows) {
      await _restoreWindowSize();
    }
    if (Platform.isAndroid) {
      try {
        await FlutterOverlayWindow.closeOverlay();
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  // -- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool isVisible = _gazeDetector.isScreenVisible;
    final bool showBlackout = _blackoutWanted;

    final String headerTitle;
    final String badgeText;
    final Color dotColor;
    if (_isStarting) {
      headerTitle = 'Starting Shield';
      badgeText = 'INIT';
      dotColor = C.cocoa;
    } else if (_error != null) {
      headerTitle = 'Sensor Error';
      badgeText = 'FAULT';
      dotColor = C.caramel;
    } else {
      headerTitle = 'Shield Active';
      badgeText = isVisible ? 'CLEAR' : 'VEILED';
      dotColor = isVisible ? C.olive : C.caramel;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
          backgroundColor: C.beige,
          body: Column(
            children: [
              if (Platform.isWindows)
                HideArHeader(
                  title: headerTitle,
                  badgeText: badgeText,
                  badgeDotColor: dotColor,
                  onBack: _stopProtection,
                  onMinimise: () => windowManager.hide(),
                  onClose: exitHideAr,
                  onDragStart: () => windowManager.startDragging(),
                ),
              Expanded(
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(S.x4),
                    child: _buildBody(isVisible),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showBlackout && Platform.isWindows) _buildBlackout(),
      ],
    );
  }

  Widget _buildBody(bool isVisible) {
    if (_isStarting) return _buildStarting();
    if (_error != null) return _buildErrorState();
    return _buildStatus(isVisible);
  }

  Widget _buildStarting() {
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
                  Icons.shield_outlined,
                  color: C.beige,
                  size: 22,
                ),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Waking Camera', style: T.heading),
                    const SizedBox(height: 2),
                    Text('Preparing on-device face geometry', style: T.body),
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

  Widget _buildErrorState() {
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
                      Icons.error_outline_rounded,
                      color: C.beige,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(child: Text('Sensor Interrupted', style: T.heading)),
                ],
              ),
              const SizedBox(height: S.x3),
              Text(_error!, style: T.body),
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        ActionPillButton(
          label: 'Retry Sensor',
          primary: true,
          icon: Icons.refresh_rounded,
          onPressed: _startCamera,
        ),
        const SizedBox(height: S.x2),
        ActionPillButton(
          label: 'Disable Shield',
          tonal: true,
          onPressed: _stopProtection,
        ),
      ],
    );
  }

  // -- Live Dashboard -------------------------------------------------------

  Widget _buildStatus(bool isVisible) {
    final CameraController? controller = _cameraGazeService.controller;
    final Uint8List? nativeFrame = _cameraGazeService.lastFrameBytes;
    final bool wantPreview = SettingsService.instance.showCameraPreview;
    final HeadPose? pose = _cameraGazeService.lastPose;
    final int failures = _cameraGazeService.shredFailures;
    final CameraEffects effects = _cameraGazeService.effects;
    final bool shoulderLimited =
        _gazeDetector.detectShoulderSurfers &&
        (_cameraGazeService.isVirtualCamera || effects.hidesOthers);

    final Color bannerBg = isVisible ? C.espresso : C.caramel;
    final Color bannerBorder = isVisible ? C.roast : C.caramel;
    final double progress = isVisible ? 1.0 : _gazeDetector.confidence;
    final IconData statusIcon =
        isVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded;
    final String lockHint =
        isVisible
            ? 'Attentive lock active'
            : 'Frames to unlock: ${_gazeDetector.framesToReveal}';

    Widget? previewWidget;
    if (wantPreview) {
      if (controller != null && controller.value.isInitialized) {
        final double ratio = controller.value.aspectRatio;
        previewWidget = AspectRatio(
          aspectRatio: ratio == 0 ? 4 / 3 : ratio,
          child: CameraPreview(controller),
        );
      } else if (nativeFrame != null) {
        previewWidget = Image.memory(
          nativeFrame,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
        );
      }
    }

    final bool inMemory = _cameraGazeService.isInMemoryCapture;
    final String captureLabel =
        inMemory ? 'RAM ($_captureModeLabel)' : 'Disk ($_captureModeLabel)';
    final String yawLabel =
        pose == null ? '--' : '${pose.yaw.toStringAsFixed(1)}°';
    final String rollLabel =
        pose == null ? '--' : '${pose.roll.toStringAsFixed(1)}°';
    final String tuneLabel =
        _cameraGazeService.isPitchCalibrated ? 'Ready' : 'Learn';
    final int shredded = _cameraGazeService.framesShredded;
    final String wipedLabel =
        failures == 0 ? '$shredded' : '$shredded ($failures failed)';
    const EdgeInsets metricPadding =
        EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfaceCard(
          color: bannerBg,
          borderColor: bannerBorder,
          padding: const EdgeInsets.all(S.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: C.beige.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                    child: Icon(statusIcon, color: C.beige, size: 20),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isVisible ? 'Display Clear' : 'Display Veiled',
                          style: T.hero.copyWith(color: C.beige, fontSize: 21),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _gazeDetector.reason.message,
                          style: T.body.copyWith(color: C.sandDeep),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x4),
              VeilProgressBar(progress: progress, color: C.beige),
              const SizedBox(height: S.x2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    lockHint,
                    style: T.caption.copyWith(
                      color: C.sandDeep,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${(progress * 100).round()}%',
                    style: T.caption.copyWith(color: C.beige),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (previewWidget != null) ...[
          const SizedBox(height: S.x3),
          SurfaceCard(
            padding: const EdgeInsets.all(S.x2),
            child: Stack(
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(R.md),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 145),
                      child: previewWidget,
                    ),
                  ),
                ),
                Positioned(
                  top: S.x2,
                  left: S.x2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: S.x2,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: C.espresso.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(R.pill),
                    ),
                    child: Text(
                      'LIVE SENSOR',
                      style: T.caption.copyWith(color: C.beige, fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: S.x3),
        Row(
          children: [
            Expanded(
              child: BentoTile(
                icon: Icons.swap_horiz_rounded,
                label: 'Yaw',
                value: yawLabel,
              ),
            ),
            const SizedBox(width: S.x2),
            Expanded(
              child: BentoTile(
                icon: Icons.rotate_right_rounded,
                label: 'Roll',
                value: rollLabel,
              ),
            ),
            const SizedBox(width: S.x2),
            Expanded(
              child: BentoTile(
                icon: Icons.center_focus_strong_rounded,
                label: 'Tune',
                value: tuneLabel,
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x2 + 2),
        Row(
          children: [
            Expanded(
              child: BentoTile(
                icon: Icons.memory_rounded,
                label: 'Capture',
                value: captureLabel,
                valueColor: inMemory ? C.olive : C.espresso,
                toneColor: inMemory ? C.oliveSoft : C.sandDeep,
              ),
            ),
            const SizedBox(width: S.x2 + 2),
            Expanded(
              child: BentoTile(
                icon: Icons.group_outlined,
                label: 'Bystander',
                value: _shoulderLabel,
                valueColor: shoulderLimited ? C.caramel : C.espresso,
                toneColor: shoulderLimited ? C.caramelSoft : C.sandDeep,
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x2 + 2),
        SurfaceCard(
          padding: metricPadding,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Camera Effects', style: T.caption),
                    const SizedBox(height: 2),
                    Text(
                      effects.summary,
                      style: T.value.copyWith(
                        fontSize: 12.5,
                        color: effects.hidesOthers ? C.caramel : C.espresso,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 28, color: C.border),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Temp Wiped', style: T.caption),
                    const SizedBox(height: 2),
                    Text(
                      wipedLabel,
                      style: T.value.copyWith(
                        fontSize: 12.5,
                        color: failures == 0 ? C.espresso : C.caramel,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        if (Platform.isWindows) ...[
          ActionPillButton(
            label: 'Minimise to Tray',
            tonal: true,
            icon: Icons.horizontal_rule_rounded,
            onPressed: () => windowManager.hide(),
          ),
          const SizedBox(height: S.x2),
        ],
        ActionPillButton(
          label: 'Disable Shield',
          danger: true,
          icon: Icons.power_settings_new_rounded,
          onPressed: _stopProtection,
        ),
      ],
    );
  }

  String get _shoulderLabel {
    if (!_gazeDetector.detectShoulderSurfers) return 'Off';
    if (_cameraGazeService.isVirtualCamera) return 'Limited (Virtual)';
    final CameraEffects effects = _cameraGazeService.effects;
    if (effects.backgroundBlur == true) return 'Limited (Blur)';
    if (effects.autoFraming == true) return 'Limited (Framing)';
    return 'Watching';
  }

  String get _captureModeLabel {
    if (_cameraGazeService.isInMemoryCapture) {
      return '${_cameraGazeService.frameWidth}x${_cameraGazeService.frameHeight}';
    }
    final ResolutionPreset? p = _cameraGazeService.activeResolution;
    return switch (p) {
      ResolutionPreset.low => '240p',
      ResolutionPreset.medium => '480p',
      ResolutionPreset.high => '720p',
      ResolutionPreset.veryHigh => '1080p',
      ResolutionPreset.ultraHigh => '2160p',
      ResolutionPreset.max => 'max',
      null => '--',
    };
  }

  // -- Fullscreen Espresso Veil ---------------------------------------------

  Widget _buildBlackout() {
    return ColoredBox(
      color: C.espressoDeep,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(S.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: C.espresso,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: C.sand.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.visibility_off_rounded,
                  size: 36,
                  color: C.beige,
                ),
              ),
              const SizedBox(height: S.x5),
              Text(
                'Display Concealed',
                textAlign: TextAlign.center,
                style: T.hero.copyWith(color: C.beige, fontSize: 32),
              ),
              const SizedBox(height: S.x3),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: S.x4,
                  vertical: S.x2,
                ),
                decoration: BoxDecoration(
                  color: C.roast,
                  borderRadius: BorderRadius.circular(R.pill),
                  border: Border.all(color: C.caramel),
                ),
                child: Text(
                  _gazeDetector.reason.message.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: T.caption.copyWith(color: C.beige, letterSpacing: 1.0),
                ),
              ),
              const SizedBox(height: S.x6),
              SizedBox(
                width: 210,
                child: ActionPillButton(
                  label: 'Disable Shield',
                  onPressed: _stopProtection,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
