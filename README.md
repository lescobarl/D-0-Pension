# d_0_pension

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Golden tests (pixel-perfect)

Regresión visual de referencia (390×844 @ dpr 1.0) contra imágenes PNG
commiteadas en [`test/goldens/`](test/goldens/):

- [`test/theme_golden_test.dart`](test/theme_golden_test.dart) → `goldens/theme_showcase.png`
- [`test/pension_card_golden_test.dart`](test/pension_card_golden_test.dart) → `goldens/pension_card.png`, `goldens/rows_and_notes.png`
- [`test/home_tabs_golden_test.dart`](test/home_tabs_golden_test.dart) → `goldens/home_tabs_shell.png`

### Regenerar las imágenes

```sh
flutter test test/theme_golden_test.dart test/pension_card_golden_test.dart test/home_tabs_golden_test.dart --update-goldens
```

Regenerar es **obligatorio** tras cualquier cambio visual intencional; correr los
tests sin `--update-goldens` valida que no haya cambios de píxel respecto a la
referencia (falla en cuanto un `RenderFlex` se desborda o cambia un color/tamaño).

### Sin dependencias externas

La infraestructura es 100% dependencia-cero (coherente con la filosofía del
proyecto):

- [`test/golden_fonts.dart`](test/golden_fonts.dart) carga Roboto + MaterialIcons
  reales desde la caché del SDK (`bin/cache/artifacts/material_fonts/`) para que
  los glifos no se rendericen como cajas Ahem.
- [`test/golden_harness.dart`](test/golden_harness.dart) fija la superficie
  (390×844, dpr 1.0) y provee `pumpUntilFound()` (evita los colgados de
  `pumpAndSettle`).

### Determinismo cross-platform

Los PNG se generan con el motor de software del SDK (misma versión Flutter 3.41.5,
mismos TTF de la caché, mismo rasterizador) en Windows local y en el runner
ubuntu-latest de CI, por lo que las referencias son deterministas entre
plataformas. El job `test` de `.github/workflows/flutter-ci.yml` ya incluye los
3 archivos golden en su conjunto curado.
