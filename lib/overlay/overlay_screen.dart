// Fullscreen overlay shown when user looks away. Used on Android (over other apps).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../theme/tokens.dart';

class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key});

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> {
  bool _isLooking = true;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = FlutterOverlayWindow.overlayListener.listen((event) {
      final String msg = event?.toString() ?? '';
      final isLooking = msg == 'looking';
      if (mounted && _isLooking != isLooking) {
        setState(() => _isLooking = isLooking);
        try {
          FlutterOverlayWindow.updateFlag(
            isLooking ? OverlayFlag.clickThrough : OverlayFlag.defaultFlag,
          );
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SizedBox.expand(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 240),
          opacity: _isLooking ? 0.0 : 1.0,
          child:
              _isLooking
                  ? const SizedBox.shrink()
                  : Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: C.espressoDeep.withValues(alpha: 0.94),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 84,
                            height: 84,
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
                              size: 40,
                              color: C.beige,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Display Concealed',
                            style: T.hero.copyWith(
                              color: C.beige,
                              fontSize: 26,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Look back at the screen to continue',
                            style: T.body.copyWith(
                              color: C.sandDeep,
                              fontSize: 15,
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
