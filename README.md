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

Los baselines son **autoritativos para la plataforma de CI** (ubuntu-latest): el
rasterizado de texto difiere entre SO (FreeType en Linux vs DirectWrite en
Windows), por lo que las imágenes deben generarse en el mismo entorno que las
valida. Tras un cambio visual intencional, regenere con el workflow
`Update Golden Baselines` ([`.github/workflows/golden-update.yml`](.github/workflows/golden-update.yml))
y descargue los PNG generados en Linux:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/update_goldens_ci.ps1
```

El script dispara el workflow, espera a que termine, descarga el artefacto
`goldens` y copia los PNG en [`test/goldens/`](test/goldens/). Luego haga commit
de los cambios y el job `test` de CI validará los baselines en modo estricto.
(`-SkipTrigger` re-descarga el artefacto del run más reciente sin disparar uno
nuevo.)

Localmente también se pueden regenerar en el SO del desarrollador:

```sh
flutter test test/theme_golden_test.dart test/pension_card_golden_test.dart test/home_tabs_golden_test.dart --update-goldens
```

> **Nota cross-platform:** en Windows local los tests golden pueden reportar
> pequeñas diferencias de píxel (≈0.9%–6.7% por antialiasing/hinting de texto)
> contra los baselines commiteados, porque fueron generados con el rasterizador
> de Linux. Es el comportamiento esperado y documentado de los golden tests con
> texto; la autoridad es el runner ubuntu-latest de CI. Para sincronizar, use el
> workflow anterior.

### Sin dependencias externas

La infraestructura es 100% dependencia-cero (coherente con la filosofía del
proyecto):

- [`test/golden_fonts.dart`](test/golden_fonts.dart) carga Roboto + MaterialIcons
  reales desde las copias empaquetadas en [`test/fonts/`](test/fonts/) (byte-idénticas
  a las del SDK, licencia Apache-2.0 incluida) para que los glifos no se rendericen
  como cajas Ahem. Cae a la caché del SDK (`bin/cache/artifacts/material_fonts/`)
  solo si el directorio del repo no existe.
- [`test/golden_harness.dart`](test/golden_harness.dart) fija la superficie
  (390×844, dpr 1.0) y provee `pumpUntilFound()` (evita los colgados de
  `pumpAndSettle`).

### Determinismo cross-platform

Las fuentes se toman siempre de [`test/fonts/`](test/fonts/) (mismas copias del SDK
3.41.x en cualquier máquina), por lo que los PNG se renderizan con el mismo motor de
software del SDK en Windows local y en el runner ubuntu-latest de CI sin depender de
la caché de artefactos (que en Linux no incluye `material_fonts`). El job `test` de
`.github/workflows/flutter-ci.yml` ya incluye los 3 archivos golden en su conjunto
curado.
