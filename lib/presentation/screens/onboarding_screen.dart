import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../core/theme/app_theme.dart';
import '../../services/billing/payment_provider.dart';

/// Onboarding screen — plays the branded intro video and then continues to
/// the login screen automatically (Opción A).
///
/// Uses `assets/videos/onboarding_intro.mp4`. If the video cannot be loaded
/// (missing asset, unsupported codec, etc.) the user is taken directly to
/// login so onboarding never blocks.
///
/// En web los navegadores bloquean el autoplay con sonido, por lo que el video
/// arranca en silencio (muted) y se muestra un botón para activar el audio.
///
/// Flujo (Opción A):
///   - El botón "Saltar" es visible desde el inicio.
///   - Cuando el video termina, se avanza automáticamente a `/login` tras un
///     breve margen (~1.5 s) para no cortar el último fotograma.
///   - Si el video falla o no termina en 30 s, también se avanza a `/login`.
///   - No hay botón "Comenzar": el onboarding siempre continúa solo.
///
/// Ported from machote's `OnboardingScreen` (~389 lines).
/// Adaptations:
///   - Uses [AppTheme] instead of `FamilyTheme`
///   - Uses [PaymentProvider] instead of BLoC
///   - Uses default Material fonts instead of `GoogleFonts.nunito()`
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoError = false;

  // En web los navegadores bloquean el autoplay con sonido, así que el video
  // arranca en silencio y el usuario activa el audio con el botón.
  bool _muted = kIsWeb;

  // Último recurso: si el video ni termina ni falla (p. ej. autoplay bloqueado
  // o codec no soportado), se avanza a login para no bloquear al usuario.
  Timer? _fallbackTimer;

  // Auto-avance agendado cuando el video termina (breve margen antes del login).
  Timer? _advanceTimer;

  // Evita navegar dos veces (video termina + timer de fallback, etc.).
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
    _fallbackTimer = Timer(const Duration(seconds: 30), _goToLogin);
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.asset(
        'assets/videos/onboarding_intro.mp4',
      );
      await controller.initialize();
      controller.setLooping(false);
      controller.setVolume(_muted ? 0.0 : 1.0);
      controller.addListener(_onVideoEvent);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
        _videoInitialized = true;
      });
      controller.play();
    } catch (e) {
      // El video no está disponible: se muestra el fallback estático un
      // instante y se continúa directo al login.
      if (mounted) {
        setState(() => _videoError = true);
        _goToLogin();
      }
    }
  }

  /// Activa/desactiva el audio. En web la primera interacción del usuario
  /// desbloquea el autoplay, así que aquí se reanuda la reproducción si estaba
  /// detenida por la política del navegador.
  void _toggleMute() {
    final controller = _videoController;
    if (controller == null) return;
    setState(() => _muted = !_muted);
    controller.setVolume(_muted ? 0.0 : 1.0);
    if (!_muted && !controller.value.isPlaying) {
      controller.play();
    }
  }

  void _onVideoEvent() {
    if (!mounted || _videoController == null) return;
    if (_videoController!.value.isCompleted) {
      _scheduleAutoAdvance();
    }
  }

  /// Cuando el video termina, deja un breve margen para que el usuario vea el
  /// último fotograma y luego avanza a login automáticamente.
  void _scheduleAutoAdvance() {
    if (_advanceTimer != null) return; // ya agendado
    _advanceTimer = Timer(const Duration(milliseconds: 1500), _goToLogin);
  }

  /// Marca el onboarding como completado y navega a `/login`.
  ///
  /// Es seguro llamarlo varias veces: solo la primera invocación navega.
  void _goToLogin() {
    _fallbackTimer?.cancel();
    _advanceTimer?.cancel();
    if (!mounted || _navigated) return;
    _navigated = true;
    final provider = context.read<PaymentProvider>();
    provider.completeOnboarding();
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _advanceTimer?.cancel();
    _videoController?.removeListener(_onVideoEvent);
    _videoController?.dispose();
    super.dispose();
  }

  /// Static fallback shown while the video is loading or when it failed
  /// (solo un instante, porque en fallo se continúa a login).
  Widget _buildFallback() {
    return Column(
      children: [
        const Spacer(flex: 2),
        // App icon (logo oficial de la app)
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Image.asset(
            'assets/icons/app_icon_512.png',
            width: 128,
            height: 128,
            fit: BoxFit.cover,
          ),
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
      ],
    );
  }

  /// The intro video, centered and fitted to the screen.
  Widget _buildVideo() {
    final controller = _videoController!;
    final aspectRatio = controller.value.aspectRatio;
    return Center(
      child: Container(
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  /// Botón "Saltar": siempre visible para ir al login sin esperar al video.
  Widget _buildSkipButton() {
    return TextButton(
      onPressed: _goToLogin,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: 0.26),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      child: const Text(
        'Saltar',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Botón para activar/desactivar el audio del video.
  Widget _buildSoundToggle() {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: _muted ? 'Activar sonido' : 'Silenciar',
        onPressed: _toggleMute,
        icon: Icon(
          _muted ? Icons.volume_off : Icons.volume_up,
          size: 20,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showVideo = _videoInitialized && !_videoError;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video or static fallback
            showVideo ? _buildVideo() : _buildFallback(),
            // Sound toggle (web arranca en silencio para permitir autoplay).
            if (showVideo)
              Positioned(top: 8, right: 8, child: _buildSoundToggle()),
            // Botón Saltar: fijo al borde inferior, fuera de los subtítulos.
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildSkipButton(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
