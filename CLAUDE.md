# D-0-Pension — Reglas Absolutas de Ingeniería

> Este archivo es vinculante. El agente DEBE leer y cumplir todas las reglas aquí definidas antes de cualquier operación.
> Este es el ÚNICO archivo de constraints. No existen archivos duplicados.

---

## 1. PROHIBICIONES ABSOLUTAS

| # | Regla | Descripción |
|---|-------|-------------|
| 0 |NO! notificar hasta tener 100% validado| se debe notificar la conclusion de una tarea hasta que este 100% validada , con prubas productivas|
| 0.0 | ⏳ NO timeout:null en comandos | Prohibido usar `timeout: null` en `execute_command`. Todo comando debe tener un timeout finito (máx. 30s para comandos rápidos, máx. 120s para instalaciones). Para servidores largos (vite, npm start, flutter run, etc.), usar timeout de 15-30s solo para verificar arranque y luego verificar con otro comando. El uso de `timeout: null` causa el botón "Run" y bloquea el chat. |
| 0.1 |Integra en tus validaciones screenshot para que certifiques que todo esta bien!|
| 0.2 |No esta permitido genracion de objetos dummy todo debe ser perfectamente funional|
| 0.3 |Las validaciones y pruebas deben incluir auditorias visuales , funcionales y tecnicas completas asegurando funcionalidad y visualizacion completa|
| 1 | ❌ NO ENTREGAS PARCIALES O SIN VALIDAR | Cada tarea resuelta debe estar completa , validada tanto funcional como visualmente  |
| 1 | ❌ NO HARDCODE | Toda configuración debe venir de variables de entorno, archivos de configuración o inyección de dependencias. Prohibido escribir valores quemados en el código. |
| 2 | ❌ NO PARCHES | Si se detecta un error, se debe corregir de fondo. No se permiten parches de código para casos de borde. Cero soluciones temporales. |
| 3 | ❌ NO `new` en lógica de negocio | Prohibida la instanciación directa de clases con operador `new` dentro de la lógica de negocio. Toda dependencia debe inyectarse mediante interfaces. |
| 4 | ❌ NO commits directos a `main`/`master` | El flujo de desarrollo exige ramas de características aisladas (`feature/*`). Prohibido commitear directo a producción. |
| 5 | ❌ NO try-catch vacíos | No se permiten bloques try-catch vacíos o que silencien errores. Toda excepción debe ser capturada, registrada en el log de auditoría y propagada con contexto descriptivo. |
| 6 | ❌ NO modificar +2 archivos de dominio sin interfaz común | Si una tarea requiere modificar más de dos archivos de dominio distintos, el agente debe proponer primero un diseño de interfaz común antes de implementar. |
| 7 | ❌ NO cambios temporales o rutas dobles | Cualquier cambio debe ser realizado de fondo. No se permiten archivos duplicados para prueba, comentarios de código legacy, ni implementaciones paralelas. |
| 8 | ❌ NO borrado físico en offline | El borrado es estrictamente lógico (`deleted: true`), nunca físico en offline. |
| 9 | ❌ NO a entregas parciales, todo se debe entregar completo de acuerdo a la solicitud |
| 10 | ❌ NO a grandes respuestas, solo cualdo se solicita el detalle responder detalladamente, de modo contrario responder en resumen lo mas claro y preciso posible |

## 2. OBLIGACIONES ESTRICTAS

| # | Regla | Descripción |
|---|-------|-------------|
| 1 | ✅ Inyección de Dependencias | Toda dependencia debe ser inyectada mediante interfaces. Prohibida la instanciación directa. Garantiza desacoplación total y testabilidad. |
| 2 | ✅ JSDoc en todo componente/método | Todo nuevo componente o método debe incluir comentarios JSDoc que expliquen el contrato de la interfaz, no la implementación interna. |
| 3 | ✅ Principio de Responsabilidad Única (SRP) | Cada archivo/clase debe tener una única razón para cambiar. |
| 4 | ✅ Tests de inmutabilidad | Toda pieza desarrollada debe incluir un test que valide que la arquitectura sigue siendo agnóstica al negocio tras los cambios. |
| 5 | ✅ Log de auditoría | Todo cambio en configuración debe ser registrado en un log inmutable de auditoría. |
| 6 | ✅ UUIDv4 en toda inserción | Queda estrictamente prohibido el uso de llaves numéricas secuenciales. Toda inserción genera UUIDv4 en texto plano. |
| 7 | ✅ Tupla de sincronización obligatoria | Cada tabla incorpora obligatoriamente `[revision, updated_at, deleted]`. Las modificaciones incrementan `revision` atómicamente y actualizan `updated_at` en UTC. |
| 8 | ✅ Gestión de errores con contexto | Toda excepción debe ser capturada, registrada en el log de auditoría y propagada con un contexto descriptivo. |
| 9 | ✅ Aislamiento de contexto de IA | Cada llamada de inferencia debe inicializar un contexto ciego aislado: `escuela_id + alumno_id + materia_id`. Purgar variables globales residuales antes de cada inferencia. |
| 10 | ✅ Circular Buffer en audio | El pipeline de audio debe implementar vaciado cíclico cada 30 segundos para evitar fugas de memoria. |
| 11 | ✅ requestAnimationFrame para 3D | El renderizado 3D del avatar debe aislarse con `requestAnimationFrame`. Comunicación con IndexedDB via `postMessage`. |

## 3. STACK TECNOLÓGICO OBLIGATORIO

| Capa | Tecnología | Propósito |
|------|-----------|-----------|
| Lenguaje | TypeScript (estricto) | Tipado seguro |
| Build | Vite 5 + React 18 | Rapidez, HMR, PWA |
| Routing | React Router v6 | Navegación lazy de módulos |
| Estado Global | Zustand | Ligero, persistencia selectiva |
| DB Local | Dexie.js (wrapper IndexedDB) | Versioning, queries reactivas |
| Estilos | Tailwind CSS 3 | Utility-first, purge automático |
| PWA | vite-plugin-pwa | Service Worker, caching offline |
| Testing | Vitest + React Testing Library | Tests de inmutabilidad |
| 3D Avatar | Three.js + @react-three/fiber | Renderizado 3D offline |
| IA Local | WebLLM + Orama + Whisper WASM + Piper TTS + Rhubarb WASM | Edge computing completo |

## 4. CONVENCIONES DE CÓDIGO

- **Archivos**: PascalCase para componentes (`FluAvatar.tsx`), camelCase para hooks/utils (`useAvatarState.ts`)
- **Un componente por archivo**: Cada archivo exporta un único componente principal
- **Estructura de carpetas**: `src/modules/[bloque]/[modulo]/Componente.tsx`
- **Interfaces**: Prefijo `I` (ej. `IAvatarState`), tipos sin prefijo
- **Archivos de tipos**: `src/types/[dominio].ts`

## 5. ESTRUCTURA DEL PROYECTO

```
flu-os/
├── public/
│   ├── models/          # Modelos 3D (FBX, GLTF)
│   ├── seeds/           # Archivos JSON de carga inicial
│   └── sounds/          # Assets de audio
├── src/
│   ├── components/      # Componentes compartidos
│   ├── core/            # Lógica de negocio pura (sin React)
│   │   ├── ai/          # Motores de IA
│   │   ├── db/          # Base de datos y repositorios
│   │   └── sync/        # Motor de sincronización
│   ├── hooks/           # Custom hooks de React
│   ├── modules/         # Módulos de interfaz (lazy loaded)
│   │   ├── flu/         # Bloque de identidad core
│   │   ├── operaciones/ # Bloque de aula
│   │   ├── gestion/     # Bloque escolar
│   │   └── configuracion/ # Bloque de infraestructura
│   ├── routes/          # Configuración de rutas
│   ├── store/           # Stores de Zustand
│   ├── types/           # Tipos e interfaces globales
│   └── utils/           # Utilidades
├── plans/               # Planes de módulos (especificaciones para Code)
├── CONTEXTO_FLU_OS2.md  # Especificación completa del proyecto
├── CLAUDE.md            # Este archivo (reglas vinculantes — ÚNICO archivo de reglas)
└── tailwind.config.js
```

## 6. VALIDACIÓN PRE-COMMIT

Antes de realizar un commit, el agente DEBE:
1. Ejecutar `npm run test` y confirmar que todos los tests pasan
2. Verificar que no hay código hardcodeado
3. Verificar que no hay try-catch vacíos
4. Verificar que toda nueva tabla tiene tupla `[revision, updated_at, deleted]`
5. Si falla algo, revertir el último cambio automáticamente

> **📚 Especificación del proyecto:** [`CONTEXTO_FLU_OS2.md`](CONTEXTO_FLU_OS2.md) — El agente DEBE leer este archivo como fuente de especificación del sistema.

---

## 7. REGLAS ESPECÍFICAS DEL PROYECTO D-0-PENSION

| # | Regla | Descripción |
|---|-------|-------------|
| 1 | ✅ Login automático | El login debe tener email `demo@example.com` y clave `1234` prellenados por defecto. El usuario solo da Enter para acceder. |
| 2 | ✅ Campos UMA y Salario Mínimo SOLO en CAPTURA | Los campos "UMA Diaria" y "Salario Mínimo Diario" deben estar ÚNICAMENTE en la pantalla de CAPTURA (captura_view.dart). NO deben aparecer en configuración (config_view.dart) ni en pensión (pension_view.dart). |
| 3 | ✅ Reactividad UMA/SM | Al cambiar `edadRetiro` o `fechaNacimiento`, UMA y Salario Mínimo se deben actualizar automáticamente mediante proyección desde `pensionYear`. Si el usuario edita manualmente UMA o SM, la proyección automática se desactiva. |
| 4 | ✅ No sobrescribir input del usuario | El sync de TextEditingController en el Consumer builder solo debe ejecutarse cuando `umaSmAutoCalculated == true`. Nunca sobrescribir lo que el usuario está escribiendo. |
| 5 | ✅ Puerto 8080 para web | La aplicación web debe lanzarse siempre en `--web-port=8080`. |
| 6 | ✅ Validar antes de notificar | No notificar conclusión de tarea hasta haber rebuild y verificado que el cambio funciona (hot reload o nueva instancia). |
| 7 | ✅ Responder en español | Todas las respuestas al usuario deben ser en español, claras y directas. |
