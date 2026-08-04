@echo off
REM ============================================================
REM  Build web optimizado para D-0-Pension
REM  --no-wasm-dry-run: omite el análisis de compatibilidad con
REM  WebAssembly (no se compila a Wasm), reduciendo el tiempo de
REM  build de ~45-52s a ~8s.
REM ============================================================
flutter build web --no-wasm-dry-run
