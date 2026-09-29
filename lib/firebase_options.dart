import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Opciones de Firebase por plataforma (formato estándar de flutterfire).
///
/// Esta app solo integra Firebase en Android: el archivo
/// `android/app/google-services.json` (proyecto `pension-ley-73-a9f23`) es el
/// único declarado, por lo que el resto de plataformas no consumen Firebase.
class DefaultFirebaseOptions {
  /// Opciones de la app Android, tomadas de `google-services.json`.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBiaBL6HBZXJxgc-ptejnQar57L95N6Rsg',
    appId: '1:1048178732263:android:51b7a86af8081ad19cc642',
    messagingSenderId: '1048178732263',
    projectId: 'pension-ley-73-a9f23',
    storageBucket: 'pension-ley-73-a9f23.firebasestorage.app',
  );

  /// Opciones de la plataforma actual.
  ///
  /// Solo se evalúa desde Android, porque [AnalyticsService.init] hace guard
  /// de plataforma antes de llamarlo.
  static FirebaseOptions get currentPlatform => android;
}
