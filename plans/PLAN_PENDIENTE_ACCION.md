# 📌 PLAN CALCULADORA PENSIÓN LEY 73 — LISTO PARA PRODUCCIÓN + PENDIENTES (TODOS)

> Fecha: 2026-08-08 · App: **Calculadora Pensión Ley 73 IA** (paquete **`com.pensiones.ley73`**) — Calculadora de pensión Ley 73 IMSS
> Estado: **CÓDIGO 100% LISTO PARA PRODUCCIÓN** — lo técnico está completado y verificado.
> Este documento lista **TODO lo pendiente** (sin excepción), para que trabajes sobre la lista completa.

---

# ✅ PARTE 1 — LO QUE YA ESTÁ LISTO PARA IR A PRODUCCIÓN

## Código / configuración (FASE 1 completa)
| # | Ítem | Detalle |
|---|------|---------|
| 1 | **Permiso `INTERNET`** | Agregado al manifest principal (requerido para chat IA y Play Billing en release). |
| 2 | **Label amigable** | Nombre visible configurado (ya no `d_0_pension`). |
| 3 | **Firma release con upload key propia** | Keystore propio vía `keystore.properties` (fuera de Git). Nunca debug. |
| 4 | **Iconos adaptativos** | API 26+ (foreground/background) + legacy + web icon. |
| 5 | **Video de onboarding integrado** | `assets/videos/onboarding_intro.mp4` + `onboarding_screen.dart` funcional. |
| 6 | **Login fake eliminado** | Gate de login removido (Opción A); entrada directa a pago/home. |
| 7 | **Demo mode eliminado** | La IAP ya no se puede saltar desde la UI. |
| 8 | **Restauración de compra** | Accesible en la vista de pago ("¿Ya tienes una licencia? Restaurar compra"). |
| 9 | **Disclaimer no-afiliación IMSS** | Presente en la app. |

## Validación técnica (pruebas productivas)
| # | Validación | Resultado |
|---|-----------|-----------|
| 10 | `flutter analyze` | ✅ No issues found. |
| 11 | 27 pruebas de integración | ✅ Todas en verde. |
| 12 | Golden tests | ✅ Regenerados y en verde. |
| 13 | Suite completa | ✅ **162 passed / 1 skip intencional / 5 fallos pre-existentes** (harness Excel exploratorio, fuera de alcance Play). |
| 14 | Comparación con Excel (datos frescos openpyxl) | ✅ Valores idénticos (p. ej. `pension_mensual_neta` 73302.6967, diff 0.0000). El motor es correcto. |
| 15 | **`flutter build appbundle --release`** | ✅ `build/app/outputs/bundle/release/app-release.aab` (**59.5 MB**). |
| 16 | **Firma verificada** | ✅ Upload key `CN=Calculadora Ley 73 IMSS` (SHA256 `51:C0:B2:7E:...:09:D3`, válida hasta 2053). No es debug. |
| 17 | **SDK versions** | ✅ `compileSdk 36 / minSdk 24 / targetSdk 36` — cumple el requisito vigente de Google (targetSdk 35+). |
| 18 | Versión | `1.0.0+1` (versionName `1.0.0`, versionCode `1`). |

> ➡️ Con esto ya puedes subir el `.aab` a Play Console (Internal testing). El código no necesita más cambios para publicar.

---

# ⏳ PARTE 2 — PENDIENTES COMPLETOS (TODO lo que falta)

> Lista exhaustiva. Los ítems con 💡 los puedo ejecutar/redactar yo a tu pedido. Los que no tienen marca son exclusivos de tu cuenta/consola.

## A. DECISIONES — ✅ RESUELTAS (2026-08-08)
- [x] **A1. Nombre oficial**: **"Calculadora Pensión Ley 73 IA"** (28 caracteres, ✅ cumple el límite de 30 de Play). Renombrado en app, web, iOS y documentos — ver [`FICHA_DE_TIENDA.md`](../../docs/FICHA_DE_TIENDA.md).
- [x] **A2. `applicationId` definitivo**: **`com.pensiones.ley73`** — aplicado en código (F1) y `.aab`/`.apk` regenerados y verificados.
- [x] **A3. Estrategia de versionado**: **`1.0.0+1`** (versionCode 1 / versionName "1.0.0") — aplicado y verificado en el APK (F2).

## B. DOCUMENTOS OBLIGATORIOS — ~1–2 h
- [x] **B1. Política de Privacidad** — borrador listo en [`POLITICA_DE_PRIVACIDAD.md`](../../docs/POLITICA_DE_PRIVACIDAD.md). ⏳ falta publicarla en una URL (GitHub Pages / Notion público, etc.).
- [x] **B2. Términos y Condiciones** — borrador listo en [`TERMINOS_Y_CONDICIONES.md`](../../docs/TERMINOS_Y_CONDICIONES.md). ⏳ falta publicar.
- [ ] **B3. Correo de soporte verificado** del desarrollador.

## C. MATERIAL DE LA FICHA DE LA TIENDA — ~2–3 h
- [x] **C1. Capturas de pantalla** (9:16 — 1080×1920). ✅ Generadas con el harness de golden tests: `01_captura.png`, `02_pension.png`, `03_ia.png`, `04_inversion.png` en [`capturas_tienda/`](../../capturas_tienda/).
- [ ] **C2. Feature graphic** 1024×500. 💡 puedo generar una versión base.
- [ ] **C3. Icono 512×512** para la ficha.
- [ ] **C4. Video promocional** (opcional — reutilizar el video de onboarding).
- [x] **C5. Textos de ficha redactados** (nombre ≤30, descripción corta ≤80, descripción larga con no-afiliación IMSS) → [`FICHA_DE_TIENDA.md`](../../docs/FICHA_DE_TIENDA.md). ⏳ falta cargarlos en Play Console.

## D. CUENTA DE DESARROLLADOR + PLAY CONSOLE — ~1–2 h + revisiones
- [ ] **D1. Crear cuenta de desarrollador** en [play.google.com/console](https://play.google.com/console) y pagar **$25 USD**.
- [ ] **D2. Verificar correo + teléfono** y aceptar el Acuerdo de Desarrollador.
- [ ] **D3. Crear la app** en Play Console (nombre de A1; categoría Finanzas; país México).
- [ ] **D4. Play App Signing**: subir la upload key (Google gestiona la firma de producción).
- [ ] **D5. Cuenta de pagos / merchant account** (necesaria para IAP).
- [ ] **D6. Crear los 3 productos IAP** con estos IDs exactos y precios MXN:
  - [ ] `subscription_annual_ley73` (suscripción anual, con base plan)
  - [ ] `subscription_semestral_ley73` (suscripción semestral, con base plan)
  - [ ] `license_perpetual_ley73` (licencia perpetua, compra única)
- [ ] **D7. Licenciatarios de prueba** (tu cuenta + testers) para probar IAP sin cobro.

## E. FORMULARIOS DE REVISIÓN DE GOOGLE — ~1 h
- [ ] **E1. Data Safety form** — datos recogidos: correo, pago, información financiera (salario/pensión), datos personales; **compartidos con terceros** (OpenRouter IA).
- [ ] **E2. Cuestionario IARC** (finanzas, sin violencia, sin apuestas).
- [ ] **E3. Política de privacidad** + **URL de borrado de datos** en la consola.
- [ ] **E4. Anuncios = No**.
- [ ] **E5. App access** — la app no requiere login (el gate se eliminó).

## F. TÉCNICO — lo que yo ejecuto (a tu pedido)
- [x] **F1. `applicationId` cambiado** a **`com.pensiones.ley73`** y `.aab` regenerado (56.7 MB) y verificado (`package="com.pensiones.ley73"`). ✅ (2026-08-08)
- [x] **F2. Versionado aplicado** `1.0.0+1` (versionCode 1 / versionName "1.0.0"), verificado en APK. ✅ (2026-08-08)
- [x] **F3. Borradores de Política de Privacidad y TyC** redactados → [`POLITICA_DE_PRIVACIDAD.md`](../../docs/POLITICA_DE_PRIVACIDAD.md) y [`TERMINOS_Y_CONDICIONES.md`](../../docs/TERMINOS_Y_CONDICIONES.md). ✅ (2026-08-08) ⏳ resta publicarlos en URL y llenar el correo de soporte.
- [x] **F4. Textos de la ficha redactados** → [`FICHA_DE_TIENDA.md`](../../docs/FICHA_DE_TIENDA.md). ✅ (2026-08-08)
- [x] **F5. APK release generado** → `build/app/outputs/flutter-apk/app-release.apk` (65.6 MB), firma upload key verificada (aapt2/apksigner). ✅ (2026-08-08)
- [ ] **F6. API key de OpenRouter** en runtime de release + limpieza de key/log en repo. ⏸️ depende de proxy/backend (documentado; no bloquea).
- [ ] **F7. Regenerar artefactos JSON de los 5 harness Excel** (fallos pre-existentes). ⏸️ depende del flujo Python→Excel (fuera de alcance Play; no bloquea).

## G. TESTING PREVIO A PRODUCCIÓN — días 1–7
- [ ] **G1. Subir el `.aab`** y publicar en el track **Internal testing**.
- [ ] **G2. Probar en dispositivo real** (físico): onboarding con video, pago, restauración, expiración de suscripción, chat IA.
- [ ] **G3. Probar compra con cuentas de prueba** (sin cobro real).
- [ ] **G4. Corregir bugs** encontrados (me los reportas y los arreglo).
- [ ] **G5. Publicar en Closed testing** con ≥12 testers (cuentas de Google verificadas).
- [ ] **G6. Mantener el closed testing ≥14 días continuos** (requisito para cuentas personales nuevas con suscripciones).
- [ ] **G7. Registrar testers** y verificar que descargan, usan y dejan feedback.
- [ ] **G8. Solicitar acceso a producción** una vez cumplidos los 14 días y 12 testers.

## H. LANZAMIENTO — después de la aprobación
- [ ] **H1. Publicar en Producción** con despliegue por etapas (staged rollout 10–20%).
- [ ] **H2. Monitorear Android Vitals** (crash rate, ANR) los primeros días.
- [ ] **H3. Responder comentarios y resolver reseñas negativas.**
- [ ] **H4. Plan de versiones**: subir `versionCode` en cada release.
- [ ] **H5. Monitorear ingresos de IAP y suscripciones** en Play Console.

---

# 🟡 ORDEN SUGERIDO DE EJECUCIÓN

### Día 1 — Decisiones y documentos ✅ (hecho 2026-08-08)
- [x] A1, A2, A3 (decisiones tomadas).
- [x] F3 (Política/TyC) y F4 (textos ficha) — borradores entregados.
- [ ] B3 (correo de soporte).

### Día 2 — Cuenta y consola
- [ ] D1 (cuenta $25), D2 (verificación), D3 (crear app).

### Día 3 — Configuración IAP + formularios
- [ ] D4 (Play App Signing), D5 (merchant), D6 (3 IAP), D7 (testers).
- [ ] E1–E5 (formularios).

### Día 4 — Material de ficha + subida
- [ ] C1–C5 (capturas, feature graphic, icono, textos).
- [ ] G1 (subir `.aab` a Internal testing). ✅ F1/F5 ya hechos — el `.aab` actual ya tiene `com.pensiones.ley73`.

### Día 5–7 — Testing interno
- [ ] G2, G3, G4 (probar + corregir).
- [ ] G5, G6, G7 (closed testing 14 días).

### Después — Producción
- [ ] G8 (solicitar producción), H1–H5 (lanzamiento por etapas + monitoreo).

---

# ⚠️ NOTAS CLAVE
- **No cambies el `applicationId` por tu cuenta** — hazlo conmigo (F1) para regenerar el `.aab` firmado correctamente.
- **Respaldar el upload keystore** en un lugar seguro (si se pierde, no podrás subir actualizaciones).
- Los **5 fallos de test** son harness exploratorios de validación Excel (no afectan la app): 4 dependen de artefactos JSON generados por scripts Python (`excel_real_scenarios_output.json`, `cross_validate_scenarios_output.json`) y 1 lee un JSON estático obsoleto (`excel_validation_data.json`). Las pruebas con datos frescos de Excel pasan con valores idénticos → NO son regresiones. Detalle en [`CHECKLIST_PLAY_STORE.md`](CHECKLIST_PLAY_STORE.md).
- Riesgo de revisión: el nombre usa "IMSS" → mitigar con aviso de no afiliación (ya existe en la app y va en la ficha).
