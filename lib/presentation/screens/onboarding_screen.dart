import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../services/billing/payment_provider.dart';

/// Onboarding screen — shows a branded welcome with a CTA.
///
/// When a real `assets/videos/onboarding_intro.mp4` is present, uncomment the
/// video section below to play it.  For now the screen uses a static fallback
/// (app icon + welcome text + "Continuar" button).
///
/// Ported from machote's `OnboardingScreen` (~389 lines).
/// Adaptations:
///   - Uses [AppTheme] instead of `FamilyTheme`
///   - Uses [PaymentProvider] instead of BLoC
///   - Uses default Material fonts instead of `GoogleFonts.nunito()`
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  // ---------------------------------------------------------------------------
  // Video playback (commented out – enable when onboarding_intro.mp4 exists)
  // ---------------------------------------------------------------------------
  // import 'dart:async';
  // import 'package:video_player/video_player.dart';
  //
  // class _OnboardingScreenState extends State<OnboardingScreen> {
  //   VideoPlayerController? _videoController;
  //   bool _videoInitialized = false;
  //   bool _videoError = false;
  //   bool _showCta = false;
  //   Timer? _ctaTimer;
  //
  //   @override
  //   void initState() {
  //     super.initState();
  //     _initVideo();
  //     _ctaTimer = Timer(const Duration(seconds: 3), () {
  //       if (mounted) setState(() => _showCta = true);
  //     });
  //   }
  //
  //   Future<void> _initVideo() async {
  //     try {
  //       _videoController = VideoPlayerController.asset(
  //         'assets/videos/onboarding_intro.mp4',
  //       );
  //       await _videoController!.initialize();
  //       _videoController!.setLooping(false);
  //       _videoController!.setVolume(1.0);
  //       _videoController!.addListener(_onVideoEvent);
  //       if (mounted) {
  //         setState(() => _videoInitialized = true);
  //         _videoController!.play();
  //       }
  //     } catch (e) {
  //       if (mounted) setState(() => _videoError = true);
  //     }
  //   }
  //
  //   void _onVideoEvent() {
  //     if (!mounted || _videoController == null) return;
  //     if (_videoController!.value.isCompleted) {
  //       if (mounted) setState(() => _showCta = true);
  //     }
  //   }
  //
  //   @override
  //   void dispose() {
  //     _ctaTimer?.cancel();
  //     _videoController?.removeListener(_onVideoEvent);
  //     _videoController?.dispose();
  //     super.dispose();
  //   }
  // }

  void _onContinue(BuildContext context) {
    final provider = context.read<PaymentProvider>();
    provider.completeOnboarding();
    Navigator.of(context).pushReplacementNamed('/login');
  }

  void _onSkip(BuildContext context) {
    final provider = context.read<PaymentProvider>();
    provider.completeOnboarding();
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            // App icon
            Icon(
              Icons.calculate_rounded,
              size: 100,
              color: AppTheme.accent,
            ),
            const SizedBox(height: 24),
            // Title
            Text(
              'Calculadora Ley 73',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            // Subtitle
            Text(
              'Calcula tu pensión de forma\nrápida, sencilla y 100% confiable',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 16,
                height: 1.4,
              ),
            ),
            const Spacer(flex: 1),
            // Continue button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _onContinue(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Comenzar',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Skip link
            TextButton(
              onPressed: () => _onSkip(context),
              child: Text(
                'Saltar',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 14,
                ),
              ),
            ),
            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }
}
