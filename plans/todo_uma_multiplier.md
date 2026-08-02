# TODO: Implementar Multiplicador de UMA Configurable (1-25)

## Fase 1: Modificar Backend y Provider

### 1.1. Actualizar RetroactiveProvider
- [ ] Agregar campo privado `_umaMultiplier` (double, default: 25.0)
- [ ] Agregar getter `umaMultiplier`
- [ ] Agregar método `setUmaMultiplier(double value)` con validación (1-25)
- [ ] Modificar `_projectSalarioRegistrado()` para usar `_umaMultiplier` en lugar de `PensionConstants.salarioRegistradoUmas`
- [ ] Asegurar que `setUmaMultiplier` llame a `_projectSalarioRegistrado(force: true)` y recalcule dependencias

### 1.2. Actualizar PersistenceService
- [ ] Agregar método `saveUmaMultiplier(double value)`
- [ ] Agregar método `loadUmaMultiplier()` que retorne 25.0 si no existe
- [ ] Modificar `RetroactiveProvider` para cargar/salvar el valor en `_loadFromPersistence()` y `_saveToPersistence()`

### 1.3. Actualizar FormulaEvaluator
- [ ] Verificar que `calculatePensionMod40()` ya usa `rules.maxUmaMultiplier` (sí lo hace)
- [ ] Asegurar que `rules.maxUmaMultiplier` se obtenga del provider en lugar de metadata
- [ ] O modificar para que reciba `umaMultiplier` como parámetro

## Fase 2: Actualizar UI

### 2.1. Modificar CapturaView
- [ ] Agregar control en sección "DATOS MOD40":
  - Opción: Dropdown con valores 1-25
  - O Slider con rango 1-25 y display numérico
- [ ] Conectar control al provider via `provider.setUmaMultiplier()`
- [ ] Mostrar cálculo en tiempo real: `[multiplier] × [UMA] = $[salario]`
- [ ] Agregar tooltip explicativo

### 2.2. Actualizar PensionView (opcional)
- [ ] Mostrar valor actual de UMA multiplier en sección de datos
- [ ] Asegurar que los cálculos mostrados reflejen el multiplicador configurado

## Fase 3: Testing y Validación

### 3.1. Testing Manual
- [ ] Probar cambiar multiplicador de 25 a 15
- [ ] Verificar que salario Mod40 se actualiza: `15 × UMA`
- [ ] Verificar que cálculos de ayuda asistencial se actualizan
- [ ] Probar valores límite: 1 y 25
- [ ] Verificar persistencia (recargar app)

### 3.2. Validación contra Excel
- [ ] Para multiplicador = 25, verificar que cálculos coinciden con Excel
- [ ] Para otros valores, verificar que fórmulas son consistentes

## Fase 4: Ajustes Finales

### 4.1. Documentación
- [ ] Actualizar tooltips/help text
- [ ] Agregar comentarios en código sobre el cambio

### 4.2. Limpieza
- [ ] Eliminar/actualizar `PensionConstants.salarioRegistradoUmas` si ya no se usa
- [ ] Verificar que no hay usos obsoletos de la constante

## Notas Técnicas

### Archivos Clave a Modificar:
1. `lib/services/retroactive_provider.dart` - Agregar campo y métodos
2. `lib/services/persistence_service.dart` - Persistencia
3. `lib/presentation/screens/captura_view.dart` - UI control
4. `lib/core/engine/formula_evaluator.dart` - Cálculos
5. `lib/core/utils/pension_constants.dart` - Actualizar constante

### Validaciones:
- Rango: 1-25 (inclusive)
- Tipo: double (permitir decimales si es necesario)
- Default: 25.0 para mantener compatibilidad

### Impacto en Cálculos:
1. Salario Mod40: `umaMultiplier × umaDiaria`
2. Ayuda asistencial cap1: `projectedUma × umaMultiplier × daysInYear`
3. Todos los cálculos que dependan de `salarioRegistrado`