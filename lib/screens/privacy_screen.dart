// In-app privacy mode: blurs this window when the user looks away.
// No overlay permissions needed.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../services/app_exit.dart';
import '../services/camera_gaze_service.dart';
import '../services/gaze_detector_service.dart';
import '../services/settings_service.dart';
import '../theme/tokens.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  late final GazeDetectorService _gazeDetector;
  late final CameraGazeService _cameraGazeService;

  bool _isStarting = true;
  String? _error;
  bool _showPreview = false;
  Timer? _watchdog;

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
      onGazeStateChanged: () {
        if (mounted) setState(() {});
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() {
          _isStarting = false;
          _error = msg;
        });
      },
    );
    _cameraGazeService.keepPreviewFrame = settings.showCameraPreview;
    _startCamera();
    _watchdog = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _cameraGazeService.stop();
    super.dispose();
  }

  Future<void> _startCamera() async {
    setState(() {
      _isStarting = true;
      _error = null;
    });
    try {
      await _cameraGazeService.start();
      if (mounted) setState(() => _isStarting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isStarting = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLooking = _gazeDetector.isScreenVisible;

    return Scaffold(
      backgroundColor: C.beige,
      body: Column(
        children: [
          if (Platform.isWindows)
            HideArHeader(
              title: 'Blur Preview',
              badgeText: isLooking ? 'CLEAR' : 'BLURRED',
              badgeDotColor: isLooking ? C.olive : C.caramel,
              onBack: () => Navigator.of(context).pop(),
              onMinimise: () => windowManager.hide(),
              onClose: exitHideAr,
              onDragStart: () => windowManager.startDragging(),
            ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildBackground(),
                if (!_isStarting && _error == null)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child:
                        isLooking
                            ? const SizedBox.shrink(key: ValueKey('visible'))
                            : _buildBlurOverlay(key: const ValueKey('blurred')),
                  ),
                if (!_isStarting && _error == null)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: _buildStatusChip(isLooking),
                  ),
                if (!_isStarting && _error == null && _showPreview)
                  Positioned(top: 16, right: 16, child: _buildCameraPreview()),
                if (!_isStarting && _error == null && !_showPreview)
                  Positioned(top: 16, right: 16, child: _buildPreviewToggle()),
                if (!_isStarting && _error == null)
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Center(child: _buildStopButton()),
                  ),
                if (_isStarting || _error != null) _buildLoadingOrError(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      color: C.beige,
      padding: const EdgeInsets.all(S.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 52),
          Container(
            height: 14,
            width: 170,
            decoration: BoxDecoration(
              color: C.espresso.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(R.pill),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 10,
            width: 250,
            decoration: BoxDecoration(
              color: C.cocoa.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(R.pill),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 10,
            width: 205,
            decoration: BoxDecoration(
              color: C.cocoa.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(R.pill),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            height: 92,
            decoration: BoxDecoration(
              color: C.sand,
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: C.border),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 70,
                  decoration: BoxDecoration(
                    color: C.sand,
                    borderRadius: BorderRadius.circular(R.md),
                    border: Border.all(color: C.border),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 70,
                  decoration: BoxDecoration(
                    color: C.sand,
                    borderRadius: BorderRadius.circular(R.md),
                    border: Border.all(color: C.border),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Center(
            child: Text(
              'Sample workspace canvas',
              style: T.caption.copyWith(color: C.cocoa),
            ),
          ),
          const SizedBox(height: 64),
        ],
      ),
    );
  }

  Widget _buildBlurOverlay({Key? key}) {
    return ClipRect(
      key: key,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
        child: Container(
          color: C.espressoDeep.withValues(alpha: 0.80),
          alignment: Alignment.center,
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
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.visibility_off_rounded,
                  size: 36,
                  color: C.beige,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'View Blurred',
                style: T.hero.copyWith(color: C.beige, fontSize: 22),
              ),
              const SizedBox(height: 8),
              Text(
                _gazeDetector.reason.message,
                style: T.body.copyWith(color: C.sandDeep),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isLooking) {
    final Color accent = isLooking ? C.olive : C.caramel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: C.sand,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(3, (int i) {
            final bool filled = _gazeDetector.confidence > i / 3;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: filled ? accent : C.border,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
          const SizedBox(width: 4),
          Text(
            isLooking ? 'Visible' : 'Concealed',
            style: T.caption.copyWith(color: accent),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final CameraController? controller = _cameraGazeService.controller;
    final Uint8List? nativeFrame = _cameraGazeService.lastFrameBytes;
    if ((controller == null || !controller.value.isInitialized) &&
        nativeFrame == null) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: () => setState(() => _showPreview = false),
      child: Container(
        width: 108,
        height: 82,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: C.espresso, width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(R.md - 2),
          child:
              controller != null && controller.value.isInitialized
                  ? CameraPreview(controller)
                  : Image.memory(
                    nativeFrame!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                  ),
        ),
      ),
    );
  }

  Widget _buildPreviewToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showPreview = true),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: C.sand,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: C.border),
        ),
        child: const Icon(Icons.videocam_outlined, size: 17, color: C.espresso),
      ),
    );
  }

  Widget _buildStopButton() {
    return SizedBox(
      width: 180,
      child: ActionPillButton(
        label: 'Stop Preview',
        primary: true,
        icon: Icons.stop_circle_outlined,
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _buildLoadingOrError() {
    return Container(
      color: C.espressoDeep.withValues(alpha: 0.90),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(S.x5),
      child:
          _isStarting
              ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: C.beige,
                    strokeWidth: 2.5,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Starting camera...',
                    style: T.body.copyWith(color: C.sandDeep),
                  ),
                ],
              )
              : SurfaceCard(
                padding: const EdgeInsets.all(S.x5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 38,
                      color: C.caramel,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _error ?? 'Camera error',
                      textAlign: TextAlign.center,
                      style: T.body,
                    ),
                    const SizedBox(height: 20),
                    ActionPillButton(
                      label: 'Retry',
                      primary: true,
                      onPressed: _startCamera,
                    ),
                    const SizedBox(height: S.x2),
                    ActionPillButton(
                      label: 'Go Back',
                      tonal: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
    );
  }
}
