# Plan: Implementar Multiplicador de UMA Configurable (1-25)

## Objetivo
Permitir al usuario seleccionar cuántas UMAs quiere pagar en Modalidad 40, cambiando del valor fijo actual de 25 a un valor configurable entre 1 y 25.

## Análisis Actual

### Valores Actuales Fijos:
1. `PensionConstants.salarioRegistradoUmas = 25.0` (lib/core/utils/pension_constants.dart)
2. `"max_uma_multiplier": 25` (assets/config/app_metadata.json)
3. Uso en `formula_evaluator.dart` para cálculo de ayuda asistencial (cap1)
4. Uso en `retroactive_provider.dart` para cálculo de salario Mod40

### Arquitectura Detectada:
- **Provider**: `RetroactiveProvider` tiene `_projectSalarioRegistrado()` que usa `PensionConstants.salarioRegistradoUmas`
- **UI**: Pantalla `captura_view.dart` tiene sección "DATOS MOD40" donde se podría agregar el control
- **Persistencia**: Los valores se guardan via `persistence.saveSalarioRegistrado()`

## Cambios Requeridos

### 1. Modificar Modelo de Datos
- [ ] Agregar campo `umaMultiplier` a `RetroactiveProvider`
- [ ] Agregar métodos `setUmaMultiplier()` y getter correspondiente
- [ ] Actualizar `_projectSalarioRegistrado()` para usar `_umaMultiplier` en lugar de constante fija

### 2. Actualizar Persistencia
- [ ] Agregar `saveUmaMultiplier()` y `loadUmaMultiplier()` en `PersistenceService`
- [ ] Asegurar que el valor se guarde/recupere correctamente
- [ ] Mantener compatibilidad con datos existentes (default: 25)

### 3. Modificar UI (captura_view.dart)
- [ ] Agregar control en sección "DATOS MOD40":
  - Opción 1: Dropdown con valores 1-25
  - Opción 2: Slider con rango 1-25 y display numérico
- [ ] Conectar control al provider via `setUmaMultiplier()`
- [ ] Mostrar cálculo en tiempo real: `[multiplier] × UMA = $[salario]`

### 4. Actualizar Cálculos Dependientes
- [ ] `formula_evaluator.dart`: Actualizar `calculatePensionMod40()` para usar `rules.maxUmaMultiplier` (ya existe)
- [ ] `retroactive_provider.dart`: Actualizar `_projectSalarioRegistrado()` para usar variable
- [ ] `mod40_provider.dart` y `pension_calculation_provider.dart`: Actualizar métodos relacionados

### 5. Actualizar Constantes y Configuración
- [ ] Cambiar `PensionConstants.salarioRegistradoUmas` de constante a valor obtenido del provider
- [ ] O eliminar la constante y usar directamente `_umaMultiplier`
- [ ] Actualizar `app_metadata.json`: `"max_uma_multiplier"` podría cambiar a `"default_uma_multiplier"`

### 6. Validación y Testing
- [ ] Validar que todos los cálculos se actualizan correctamente al cambiar el multiplicador
- [ ] Probar valores límite (1, 25, valores intermedios)
- [ ] Verificar que la persistencia funciona correctamente
- [ ] Asegurar que el Excel de referencia sigue siendo válido (para 25 UMAs)

## Consideraciones Especiales

### 1. Compatibilidad con Excel
- El Excel actual asume 25 UMAs fijas
- Necesitamos documentar que el valor configurable es una extensión de la funcionalidad
- Mantener 25 como valor por defecto para mantener compatibilidad

### 2. Impacto en Cálculos
- Salario Mod40: `umaMultiplier × UMA_diaria`
- Ayuda asistencial (cap1): `projectedUma × rules.maxUmaMultiplier × rules.daysInYear`
- ¿Debe usarse el mismo multiplicador en ambos lugares? **Sí**, para consistencia

### 3. Experiencia de Usuario
- El control debe estar claramente etiquetado: "UMAs a pagar en Mod40"
- Mostrar cálculo en tiempo real para feedback inmediato
- Tooltip explicativo: "Número de Unidades de Medida y Actualización que deseas pagar en Modalidad 40 (1-25)"

## Archivos a Modificar

### Core:
1. `lib/core/utils/pension_constants.dart` - Eliminar/actualizar constante
2. `lib/core/models/app_metadata.dart` - Actualizar modelo si cambiamos JSON

### Providers:
3. `lib/services/retroactive_provider.dart` - Agregar campo y métodos
4. `lib/services/persistence_service.dart` - Agregar métodos de persistencia
5. `lib/services/providers/mod40_provider.dart` - Actualizar si es necesario
6. `lib/services/providers/pension_calculation_provider.dart` - Actualizar si es necesario

### Engine:
7. `lib/core/engine/formula_evaluator.dart` - Usar valor configurable

### UI:
8. `lib/presentation/screens/captura_view.dart` - Agregar control UI
9. `lib/presentation/screens/pension_view.dart` - Mostrar valor actual si es relevante

### Configuración:
10. `assets/config/app_metadata.json` - Actualizar configuración

## Secuencia de Implementación

1. **Fase 1: Backend y Provider**
   - Modificar `RetroactiveProvider` para soportar `umaMultiplier`
   - Actualizar `PersistenceService`
   - Actualizar `formula_evaluator.dart`

2. **Fase 2: UI**
   - Agregar control en `captura_view.dart`
   - Conectar con provider
   - Agregar validación (1-25)

3. **Fase 3: Testing y Validación**
   - Probar cambios de valor
   - Verificar cálculos
   - Validar persistencia

4. **Fase 4: Documentación y Ajustes**
   - Actualizar tooltips/help text
   - Verificar que todo funciona correctamente
   - Ajustes finales de UI

## Riesgos y Mitigación

### Riesgo 1: Cálculos incorrectos
- **Mitigación**: Testing exhaustivo comparando con Excel para valor 25
- **Mitigación**: Validar fórmulas matemáticas

### Riesgo 2: Pérdida de datos existentes
- **Mitigación**: Mantener 25 como valor por defecto
- **Mitigación**: Migration script si es necesario

### Riesgo 3: Confusión del usuario
- **Mitigación**: UI clara con labels explicativos
- **Mitigación**: Tooltip con explicación de impacto

## Timeline Estimado
- **Fase 1**: 2-3 horas
- **Fase 2**: 1-2 horas  
- **Fase 3**: 1-2 horas
- **Fase 4**: 1 hora

**Total**: 5-8 horas de trabajo de desarrollo

## Notas Finales
Este cambio permitirá mayor flexibilidad a los usuarios que deseen pagar menos de 25 UMAs en Modalidad 40, manteniendo compatibilidad con el comportamiento actual (25 UMAs por defecto).