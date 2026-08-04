@echo off
REM ============================================================
REM  Build web optimizado para D-0-Pension
REM  --no-wasm-dry-run: omite el análisis de compatibilidad con
REM  WebAssembly (no se compila a Wasm), reduciendo el tiempo de
REM  build de ~45-52s a ~8s.
REM  --no-pub: omite la re-resolución de dependencias (ya están
REM  resueltas en pubspec.lock), ahorrando ~1-2s por build.
REM ============================================================
flutter build web --no-wasm-dry-run --no-pub
