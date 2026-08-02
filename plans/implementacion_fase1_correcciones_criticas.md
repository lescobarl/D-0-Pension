# Plan de Implementación - Fase 1: Correcciones Críticas

## Objetivo
Corregir los bugs más críticos identificados y mejorar la experiencia básica del usuario en 2-3 semanas.

## Bugs Prioritarios

### Bug 1: Calendario no permite fechas futuras
**Archivo**: `lib/presentation/screens/captura_view.dart`
**Línea**: 844
**Cambio**: 
```dart
// Cambiar de:
lastDate: now,
// A:
lastDate: DateTime(2100),
```

### Bug 2: No permite escribir fechas manualmente
**Archivo**: `lib/presentation/screens/captura_view.dart`
**Líneas**: 827-836
**Cambio**:
```dart
// Cambiar de:
onChanged: (v) {
  final cleaned = v.replaceAll('-', '');
  if (cleaned.length == 8 && v.length == 8 && !v.contains('-')) {
    final formatted = _autoFormatDate(v);
    controller.text = formatted;
    controller.selection = TextSelection.collapsed(offset: formatted.length);
  }
  onChanged(v);
},
// A:
onChanged: (v) {
  final cleaned = v.replaceAll('-', '');
  if (cleaned.length == 8) {
    final formatted = _autoFormatDate(cleaned);
    if (formatted != v) {
      controller.text = formatted;
      controller.selection = TextSelection.collapsed(offset: formatted.length);
    }
  }
  onChanged(v);
},
```

### Bug 3: Salario Registrado no calcula automáticamente
**Problema**: `salario_registrado` debe ser `25 × UMA_diaria_proyectada`

#### Implementación:

1. **Agregar método en `retroactive_provider.dart`**:
```dart
/// Proyecta el salario registrado como 25 UMAs × UMA diaria proyectada.
void _projectSalarioRegistrado({bool force = false}) {
  if (!force && !_salarioPromAutoCalculado) return;
  
  // Calcular: 25 UMAs × UMA diaria proyectada
  final double umaDiariaProyectada = _projectUmaDiaria();
  final double nuevoSalarioRegistrado = 25.0 * umaDiariaProyectada;
  
  if (_salarioRegistrado != nuevoSalarioRegistrado) {
    _salarioRegistrado = nuevoSalarioRegistrado;
    _recalculateCostoMod40();
    notifyListeners();
  }
}
```

2. **Modificar `setPensionYear`**:
```dart
void setPensionYear(int year) {
  if (_pensionYear == year) return;
  _pensionYear = year;
  
  // Recalcular UMA y salario mínimo
  _projectUmaSm(force: true);
  
  // Recalcular salario registrado
  _projectSalarioRegistrado(force: true);
  
  _recalculateFactAsig();
  _recalculatePensionMod40();
  _recalculateCostoMod40();
  _recalculateRetroactivo();
  _recalculateInversion();
  _recalculateFinanciamiento();
  
  _saveToPersistence();
  notifyListeners();
}
```

3. **Modificar `setUmaDiaria` para desactivar auto-cálculo**:
```dart
void setUmaDiaria(double value) {
  if (_umaDiaria == value) return;
  _umaDiaria = value;
  
  // Desactivar auto-cálculo cuando el usuario edita manualmente
  _umaSmAutoCalculated = false;
  
  // Recalcular salario registrado si está en modo auto
  if (_salarioPromAutoCalculado) {
    _projectSalarioRegistrado(force: true);
  }
  
  _recalculateFactAsig();
  _recalculatePensionMod40();
  _recalculateCostoMod40();
  _recalculateRetroactivo();
  _recalculateInversion();
  _recalculateFinanciamiento();
  
  _saveToPersistence();
  notifyListeners();
}
```

### Bug 4: Salario promedio muestra valor incorrecto al cargar
**Solución**: Asegurar que `_salarioPromedio250Semanas` se inicialice correctamente desde `app_metadata.json`

## Mejoras de UX Inmediatas

### 1. Validación Mejorada de Inputs
**Implementar en `captura_view.dart`**:
- Validación de rango para semanas (1-2500)
- Validación de fechas (no anteriores a 1900)
- Formato automático de números con separadores de miles
- Mensajes de error contextuales

### 2. Feedback Visual Mejorado
**Agregar en widgets críticos**:
- Indicadores de carga durante cálculos
- Tooltips explicativos para campos complejos
- Confirmación visual de guardado
- Estados de error claros

### 3. Navegación Mejorada
**Mejorar `home_tabs_screen.dart`**:
- Indicador visual de pestaña activa
- Scroll suave entre secciones
- Guardado automático al cambiar pestañas
- Confirmación antes de perder datos no guardados

## Plan de Testing

### Tests Unitarios a Agregar:
1. `test_salario_registrado_calculation.dart`
   - Verificar cálculo 25 × UMA
   - Verificar actualización automática al cambiar año
   - Verificar que edición manual desactiva auto-cálculo

2. `test_fecha_validation.dart`
   - Verificar fechas futuras permitidas
   - Verificar formato manual de fechas
   - Verificar validación de rangos

3. `test_ux_improvements.dart`
   - Verificar mensajes de error
   - Verificar estados de carga
   - Verificar navegación

### Tests de Integración:
1. Flujo completo de cálculo con datos reales
2. Comparación con Excel para escenarios críticos
3. Pruebas de persistencia entre sesiones

## Cronograma Semanal

### Semana 1:
- Día 1-2: Implementar Bug 1 y 2 (fechas)
- Día 3-4: Implementar Bug 3 (salario registrado)
- Día 5: Tests unitarios para bugs corregidos

### Semana 2:
- Día 1-2: Implementar validación mejorada de inputs
- Día 3-4: Implementar feedback visual mejorado
- Día 5: Tests de integración

### Semana 3:
- Día 1-2: Implementar navegación mejorada
- Día 3: Testing completo y regresión
- Día 4: Documentación de cambios
- Día 5: Preparación para release

## Métricas de Validación

### Antes/Después:
1. **Tiempo para primer cálculo**: < 30 segundos
2. **Errores de validación**: Reducir en 90%
3. **Discrepancias con Excel**: < 0.1% en cálculos clave
4. **Satisfacción de usuario**: Mejorar rating en stores

### Monitoreo Post-Release:
- Crash reports (objetivo: 0 crashes críticos)
- Tiempo de sesión promedio (objetivo: +20%)
- Tasa de abandono en onboarding (objetivo: -30%)

## Consideraciones Técnicas

### Dependencias:
- No se requieren nuevas dependencias
- Mantener compatibilidad con versiones actuales de Flutter
- No romper API existente

### Backward Compatibility:
- Mantener formato de persistencia existente
- Migración automática de datos si es necesario
- No perder configuraciones de usuarios existentes

### Performance:
- Cálculos deben mantenerse bajo 100ms
- No aumentar tamaño de app significativamente
- Mantener fluidez en dispositivos de gama baja

## Riesgos y Mitigación

### Riesgo 1: Regresión en cálculos existentes
**Mitigación**: 
- Tests exhaustivos contra Excel
- Validación con escenarios reales de usuarios
- Release gradual (beta testing)

### Riesgo 2: Problemas de persistencia
**Mitigación**:
- Backup automático antes de migraciones
- Rollback planificado
- Validación de integridad de datos

### Riesgo 3: Performance en dispositivos antiguos
**Mitigación**:
- Profiling en dispositivos de prueba
- Optimización de cálculos pesados
- Lazy loading donde sea posible

## Documentación a Actualizar

1. **README.md**: Actualizar con nuevas funcionalidades
2. **CHANGELOG.md**: Documentar todos los cambios
3. **Guía de usuario**: Actualizar screenshots y procedimientos
4. **API documentation**: Actualizar si hay cambios en interfaces públicas

## Conclusión

Esta fase 1 aborda los problemas más críticos que afectan la usabilidad y precisión de la aplicación. Las correcciones son técnicas pero tienen alto impacto en la experiencia del usuario. La implementación cuidadosa con testing exhaustivo asegurará una transición suave y mejoras tangibles en la calidad de la aplicación.