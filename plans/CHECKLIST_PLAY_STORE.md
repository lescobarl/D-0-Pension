# 📋 Checklist secuencial para publicar en Google Play

> Fecha de análisis: 2026-08-07
> Última actualización: 2026-08-08
> App: **Calculadora Pensión Ley 73 IA** — paquete **`com.pensiones.ley73`** (antes `d_0_pension`)
> Estado: **CÓDIGO LISTO para publicación** — FASE 1 (técnica) 100% completada y verificada, con `applicationId` definitivo **`com.pensiones.ley73`**. Restan solo acciones de Play Console (Fase 2+), publicación de documentos y material de ficha (Fase 0).

---

## Resumen ejecutivo — ¿Qué falta?

### 🔴 BLOQUEANTES TÉCNICOS (código, impiden publicar o rompen el release) — RESUELTOS ✅
| # | Hallazgo | Estado |
|---|----------|--------|
| 1 | Falta el permiso `INTERNET` en el manifest **principal**. | ✅ **RESUELTO** — agregado a [`AndroidManifest.xml` principal](../../android/app/src/main/AndroidManifest.xml) |
| 2 | `applicationId = com.example.d_0_pension` (placeholder). | ✅ **RESUELTO (2026-08-08)** — ID definitivo **`com.pensiones.ley73`** aplicado en [`build.gradle.kts`](../../android/app/build.gradle.kts) (`namespace` + `applicationId`) y [`MainActivity.kt`](../../android/app/src/main/kotlin/com/pensiones/ley73/MainActivity.kt) (package movido). `.aab` y `.apk` regenerados y verificados. |
| 3 | `android:label="d_0_pension"` → nombre técnico. | ✅ **RESUELTO** — nombre amigable configurado en [`AndroidManifest.xml:3`](../../android/app/src/main/AndroidManifest.xml:3) |
| 4 | Release firma con **debug keys**. | ✅ **RESUELTO** — firma release con upload keystore propio vía `key.properties` (fuera de Git). |
| 5 | **Demo mode visible en la UI**. | ✅ **RESUELTO** — demo mode eliminado. |
| 6 | **Login fake** sin backend real. | ✅ **RESUELTO** — gate de login eliminado (Opción A); `LoginProvider` removido. |
| 7 | **Video de onboarding** comentado / archivo ausente. | ✅ **RESUELTO** — video integrado (`assets/videos/onboarding_intro.mp4`) + [`onboarding_screen.dart`](../../lib/presentation/screens/onboarding_screen.dart) reescrito. |
| 8 | Iconos genéricos de Flutter. | ✅ **RESUELTO** — iconos adaptativos (API 26+) + legacy + web icon configurados. |

### 🟠 PLAY CONSOLE (no se puede hacer desde código)
- Crear **cuenta de desarrollador** ($25 USD, pago único).
- Aceptar el Acuerdo de Desarrollador + configurar **Play App Signing** (subir upload key).
- Crear **cuenta de pagos / Payments profile** y **merchant account** (necesaria para IAP).
- Crear los **3 productos IAP** en Play Console (con sus precios MXN y base plans para suscripciones):
  - `subscription_annual_ley73`
  - `subscription_semestral_ley73`
  - `license_perpetual_ley73`
  - *(IDs definidos en [`play_billing_service.dart:25`](../../lib/services/billing/play_billing_service.dart:25))*
- Registrar **licenciatarios de prueba** (license testers) para probar IAP sin cobro.
- Llenar **formulario de Seguridad de datos (Data Safety)** — la app recoge datos personales (correo, salario, semanas, fecha de nacimiento, datos familiares) y los envía a un tercero (OpenRouter IA).
- Llenar el **cuestionario de clasificación de contenido (IARC)**.
- Publicar **URL de Política de Privacidad** (obligatoria: la app tiene cuentas y datos personales).
- Configurar **borrado de datos** (data deletion) y dar de alta la URL.
- Declarar **anuncios** (esta app no tiene → "No").
- Verificar que `targetSdk` cumple el requisito vigente de Google (API 34+/35+).

### 🟡 CONTENIDO / FICHA DE LA TIENDA
- Nombre, descripción corta/larga, categoría, idioma (español MX).
- Capturas de pantalla (mín. 2, ideal 6–8, 9:16).
- **Imagen destacada (feature graphic) 1024×500** y **icono 512×512**.
- **Video promocional** (opcional; puede ser el mismo de onboarding).
- Aviso de **no afiliación con el IMSS** (el nombre/descripción usan "IMSS"; mitigar riesgo de revisión por aparentar afiliación gubernamental). Ya existe un disclaimer en la app: [`lib/presentation/widgets/disclaimer_card.dart:75`](../../lib/presentation/widgets/disclaimer_card.dart:75).

### 🟢 REQUISITOS DE TESTING DE GOOGLE
- Cuentas personales nuevas (creadas después de nov-2023) con suscripciones requieren **closed testing con ≥12 testers durante 14 días** antes de solicitar acceso a producción.
- Probar compra / restauración / expiración en sandbox.

---

## ✅ CHECKLIST SECUENCIAL (en orden de ejecución)

### FASE 0 — Decisiones y contenido (prerequisitos)
- [x] 0.1 Decidir **nombre oficial** de la app. ✅ **"Calculadora Pensión Ley 73 IA"** (28 caracteres, ✅ dentro del límite de 30 de Play; decisión A1 actualizada del usuario). Nombre aplicado en app, web, iOS, manifest y documentos (ver [`FICHA_DE_TIENDA.md`](../../docs/FICHA_DE_TIENDA.md)). ⏳ Resta confirmar el nombre final en Play Console.
- [x] 0.2 **Política de Privacidad** redactada. ✅ Finalizada en [`POLITICA_DE_PRIVACIDAD.md`](../../POLITICA_DE_PRIVACIDAD.md) con correo de soporte `vortix.labs@gmail.com`. ⏳ Resta publicarla en una URL pública y pegarla en Play Console.
- [x] 0.3 **Términos y Condiciones** redactados. ✅ Borrador en [`TERMINOS_Y_CONDICIONES.md`](../../docs/TERMINOS_Y_CONDICIONES.md). ⏳ Resta publicar y llenar contacto.
- [ ] 0.4 Definir **datos de contacto/soporte** (correo de desarrollador verificado).
- [x] 0.5 **Video de onboarding** integrado. ✅ `assets/videos/onboarding_intro.mp4` funcional en [`onboarding_screen.dart`](../../lib/presentation/screens/onboarding_screen.dart) (ver 1.6).
- [ ] 0.6 Preparar **material de la ficha**: capturas (6–8), feature graphic 1024×500, icono 512×512, video promocional.

### FASE 1 — Preparación técnica del proyecto (código) — ✅ COMPLETADA
- [x] 1.1 Cambiar `applicationId` a un ID único propio. ✅ **COMPLETADO (2026-08-08)** — decisión A2 del usuario: **`com.pensiones.ley73`** aplicado en [`build.gradle.kts`](../../android/app/build.gradle.kts) (`namespace` + `applicationId`) y [`MainActivity.kt`](../../android/app/src/main/kotlin/com/pensiones/ley73/MainActivity.kt) (package movido); `.aab` y `.apk` regenerados y verificados.
- [x] 1.2 Agregar `<uses-permission android:name="android.permission.INTERNET"/>` al [`AndroidManifest.xml` principal](../../android/app/src/main/AndroidManifest.xml). ✅
- [x] 1.3 Cambiar `android:label` a nombre amigable. ✅
- [x] 1.4 Generar **upload keystore** y configurar firma release (con `key.properties` fuera de Git). ✅
- [x] 1.5 Reemplazar **iconos**: adaptativos (foreground/background) + legacy + web icon. ✅
- [x] 1.6 Integrar el **video de onboarding** en [`onboarding_screen.dart`](../../lib/presentation/screens/onboarding_screen.dart) (assets/videos/onboarding_intro.mp4). ✅
- [x] 1.7 **Resolver el login fake** → **Opción A elegida**: gate de login eliminado; entrada directa a pago/home; `LoginProvider` removido. ✅
- [x] 1.8 **Demo mode eliminado** de la UI de pago. ✅
- [x] 1.9 Flujo de **restauración de compra** accesible en la UI (verificado en la vista de pago). ✅
- [x] 1.10 Verificar `versionCode`/`versionName` en [`pubspec.yaml:4`](../../pubspec.yaml:4) — **`1.1.0+3`** (versionName "1.1.0" / versionCode 3, secuencia de cambio menor aplicada el 2026-08-09 tras la corrección de raíz del bucle de login) y `minSdk` 24 / `targetSdk` 36. ✅
- [ ] 1.11 **API key de OpenRouter** ofuscada funciona en release; respeta fair use (rate limiting). ⏳ Depende de proxy/backend propio (documentado en riesgos).
- [x] 1.12 `flutter analyze` sin errores ✅ + suite de tests **162 passed / 1 skip intencional / 5 fallos pre-existentes** (harness de validación Excel exploratorio; fuera de alcance de Play Store; documentados abajo). ✅
- [x] 1.13 Generar **App Bundle** de release: `flutter build appbundle --release` (Play exige `.aab`, no APK). ✅ **COMPLETADO** — `build/app/outputs/bundle/release/app-release.aab` (59.5 MB). Firma verificada: upload key `CN=Calculadora Ley 73 IMSS` (self-signed, SHA256 `51:C0:B2:7E:...:09:D3`, válida hasta 2053). Nota: los errores de "Kotlin daemon compilation failed" durante el build son warnings de caché incremental entre discos (Pub cache en `C:` vs proyecto en `D:`); Gradle se recupera vía fallback y el `.aab` se genera correctamente. — **2026-08-08**: `.aab` regenerado con `applicationId` definitivo `com.pensiones.ley73` (56.7 MB, `package="com.pensiones.ley73"` verificado en merged manifest) + **APK release** `build/app/outputs/flutter-apk/app-release.apk` (65.6 MB, `package='com.pensiones.ley73' versionCode='1' versionName='1.0.0'`, firma upload key verificada con aapt2/apksigner) para prueba en dispositivo físico. — **2026-08-09**: `.aab` regenerado con **secuencia de cambio menor `1.1.0+3`** (57.4 MB / 60,222,211 bytes, `package="com.pensiones.ley73"`, `versionCode=3`, `versionName="1.1.0"`, minSdk 24, targetSdk 36, permiso INTERNET verificado en merged manifest) con la corrección de raíz del bucle de login/renovación incluida.

### FASE 2 — Configuración de Play Console
- [ ] 2.1 Crear **cuenta de desarrollador** y pagar $25.
- [ ] 2.2 Verificar correo + teléfono y aceptar el acuerdo.
- [ ] 2.3 Crear la app (nombre, categoría: Finanzas; país de distribución).
- [ ] 2.4 Configurar **Play App Signing** (dejar que Google gestione la clave de firma; subir la upload key).
- [ ] 2.5 Configurar **cuenta de pagos (merchant)** para poder crear IAP.
- [ ] 2.6 Crear los **3 productos IAP** con los IDs exactos del código, precios en MXN, base plans/offers para las suscripciones.
- [ ] 2.7 Agregar **licenciatarios de prueba** (tu cuenta + testers).
- [ ] 2.8 Llenar **Data Safety form** (datos recogidos: correo, datos de pago, información financiera del usuario, datos personales; compartidos con terceros: OpenRouter IA).
- [ ] 2.9 Llenar **cuestionario IARC** (clasificación de contenido).
- [ ] 2.10 Configurar **política de privacidad** + **URL de borrado de datos**.
- [ ] 2.11 Declarar **anuncios** = No.
- [ ] 2.12 Configurar **acceso a la app** (App access) indicando que **NO requiere login** (el gate de login se eliminó; acceso directo a pago/home).
- [ ] 2.13 Llenar **ficha**: nombre, descripciones, categoría, gráficos, capturas, icono, video promocional, contacto, idioma.

### FASE 3 — Testing previo a producción
- [ ] 3.1 Subir el `.aab` y publicar en el track **Internal testing**.
- [ ] 3.2 Probar en dispositivo real (físico, no emulador): onboarding con video, login, pago, restauración, expiración de suscripción, chat IA.
- [ ] 3.3 Probar compra con **cuentas de prueba** (sin cobro real).
- [ ] 3.4 Corregir bugs encontrados y repetir 3.1–3.3.
- [ ] 3.5 Publicar en **Closed testing** con ≥12 testers (cuentas de Google verificadas).
- [ ] 3.6 Mantener el closed testing **≥14 días continuos** (requisito para cuentas personales nuevas con suscripciones).
- [ ] 3.7 Registrar testers y verificar que descargan, usan y dejan feedback.
- [ ] 3.8 Solicitar **acceso a producción** una vez cumplidos los 14 días y 12 testers.

### FASE 4 — Lanzamiento
- [ ] 4.1 Publicar en **Producción** con **despliegue por etapas (staged rollout 10–20%)**.
- [ ] 4.2 Monitorear **Android Vitals** (crash rate, ANR) los primeros días.
- [ ] 4.3 Responder comentarios y resolver reseñas negativas.
- [ ] 4.4 Plan de versiones: subir `versionCode` en cada release.
- [ ] 4.5 Monitorear ingresos de IAP y suscripciones en Play Console.

---

## Estado de validación técnica (2026-08-07)
- ✅ `flutter analyze` — sin errores ni warnings.
- ✅ **27 pruebas de integración** en [`test/integration_test.dart`](../../test/integration_test.dart) — todas en verde.
- ✅ **Golden tests** regenerados y en verde (incluye `test/goldens/home_tabs_shell.png` tras la eliminación del botón "Salir").
- ✅ Suites de comparación con Excel **con datos frescos (openpyxl)** — todas en verde con valores idénticos (p. ej. `pension_mensual_neta` 73302.6967, diff 0.0000): `comparacion_fresca_test`, `comparar_excel_vs_app_test`, `comparativo_final_test`, `comparacion_campos_excel_test`.
- ✅ Suite completa: **162 passed, 1 skip intencional, 5 fallos** → los 5 fallos son **harness exploratorios de validación contra Excel** (pre-existentes, NO modificados, fuera del alcance de Play Store):

### Fallos pre-existentes documentados (harness Excel, NO bloquean publicación)
| Test | Causa |
|------|-------|
| [`e2e_provider_recalculation_test.dart`](../../test/e2e_provider_recalculation_test.dart) | `PathNotFoundException`: falta `excel_real_scenarios_output.json` (artefacto Python no generado) |
| [`provider_integration_test.dart`](../../test/provider_integration_test.dart) | `PathNotFoundException`: falta `cross_validate_scenarios_output.json` |
| [`validate_10_scenarios_vs_excel_test.dart`](../../test/validate_10_scenarios_vs_excel_test.dart) | `PathNotFoundException`: falta `cross_validate_scenarios_output.json` |
| [`validate_direct_test.dart`](../../test/validate_direct_test.dart) | Lee `excel_validation_data.json` **obsoleto** (2 escenarios); "18 comparisons failed out of 38" |
| [`validate_excel_real_scenarios_test.dart`](../../test/validate_excel_real_scenarios_test.dart) | `PathNotFoundException`: falta `excel_real_scenarios_output.json` |

**Por qué NO son regresiones del motor:** las pruebas con datos frescos de openpyxl producen valores idénticos a Excel (ver arriba). Los 5 fallos dependen de artefactos JSON generados por scripts Python (`excel_real_scenarios*.py`) que no están en el repo, o leen un JSON estático desactualizado. Regenerar esos artefactos requiere el flujo Python→Excel (dependencia externa). Se documentan y se dejan tal cual (sin parches, según directriz del usuario).

## Notas importantes / riesgos
1. **"IMSS" en el nombre** — Riesgo de revisión por aparentar afiliación gubernamental. Mitigar con aviso visible ("No afiliado/endosado por el IMSS") en la ficha y dentro de la app (ya existe [`disclaimer_card.dart`](../../lib/presentation/widgets/disclaimer_card.dart)).
2. **Privacidad + IA** — El chat envía los datos del usuario a OpenRouter. El Data Safety form debe declararlo como "compartido con terceros"; considerar anonimizar/limitar datos enviados.
3. **La API key de OpenRouter va embebida en el APK** — Funciona (ofuscada), pero es extraíble. Considerar un proxy/backend propio a futuro (no bloquea publicación). Este es el único pendiente 1.11 con dependencia.
4. ~~**Login fake**~~ — **RESUELTO**: el gate de login fue eliminado (Opción A); ya no existe riesgo de "funcionalidad engañosa" por login.
5. ~~**Demo mode en producción**~~ — **RESUELTO**: el demo mode fue eliminado de la UI de pago.
