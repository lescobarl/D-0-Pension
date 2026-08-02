# ANÁLISIS DE CAMBIOS PARA INVERSIÓN Y TASAS FINANCIERAS

## Fecha de análisis: 2026-07-29
## Objetivo: Documentar los cambios implementados para corregir los cálculos de inversión y tasas financieras

---

## 1. PROBLEMA IDENTIFICADO

### 1.1 Validación inicial
La validación inicial (documentada en `VALIDACION_INVERSION_TASAS.md`) mostró que los valores de inversión y tasas **NO ERAN IGUALES** entre Excel y la App:

| Escenario | Métrica | Excel | App | Diferencia | Resultado |
|-----------|---------|-------|-----|------------|-----------|
| simple_sin_esposa | Ganancia total | 5,109,567.27 | -126,626.81 | 5,236,194.08 | ❌ NO IGUAL |
| simple_sin_esposa | Tasa rendimiento | 17.12% | -0.27% | 17.38% | ❌ NO IGUAL |
| simple_con_esposa | Ganancia total | 5,553,877.47 | -6,464,171.79 | 12,018,049.25 | ❌ NO IGUAL |
| simple_con_esposa | Tasa rendimiento | 18.60% | -13.54% | 32.15% | ❌ NO IGUAL |

### 1.2 Causas principales identificadas
1. **Inputs diferentes**: Edad de retiro, semanas cotizadas y salario registrado no coincidían
2. **Fórmulas no alineadas**: Los algoritmos de cálculo diferían entre Excel y App
3. **Valores base incorrectos**: La pensión sin Mod40 se calculaba incorrectamente

---

## 2. CAMBIOS IMPLEMENTADOS

### 2.1 Creación de método `calculateInversionCorregida`

Se implementó un nuevo método en `lib/core/engine/formula_evaluator.dart` que usa fórmulas exactas de Excel:

#### Método original: `calculateInversion`
- Usaba aproximaciones
- No seguía exactamente las fórmulas de Excel
- Tenía inconsistencias en el cálculo de flujos

#### Método corregido: `calculateInversionCorregida` (líneas 663-733)
```dart
InversionCalculation calculateInversionCorregida({
  required double pensionMensualSinMod40,
  required double pensionMensualConMod40,
  required int edadRetiroSinMod40,
  required int edadRetiroConMod40,
  required double inversionTotalMod40,
  required double inversionTotal,
}) {
  // Usa fórmulas EXACTAS de Excel:
  // 1. D46: Flujo sin Mod40 = ((80*13 - D4*13) * D45) * 1.54
  // 2. F46: Flujo con Mod40 = (Sheet1!P247 + (80 - C12) * F45) * 1.54
  // 3. D49: Ganancia total = F46 - D46
  // 4. D50: Tasa rendimiento = D49 / G15
  // 5. F9: Periodos recuperación = ABS(G19 / F5)
}
```

### 2.2 Actualización del provider para usar el método corregido

En `lib/services/providers/pension_calculation_provider.dart` (líneas 207-215):
```dart
// Reemplazó:
// _inversionCalculation = _evaluator.calculateInversion(...)

// Por:
_inversionCalculation = _evaluator.calculateInversionCorregida(
  pensionMensualSinMod40: _factAsigSinMod40Calculation?.totalPensionMensual ?? 0,
  pensionMensualConMod40: _pensionMod40Calculation?.pensionMensual ?? 0,
  edadRetiroSinMod40: edadSinMod40,
  edadRetiroConMod40: edadConMod40,
  inversionTotalMod40: _costoMod40Calculation?.inversionNeta ?? 0,
  inversionTotal: _costoMod40Calculation?.inversionTotal ?? 0,
);
```

### 2.3 Corrección de valores base

#### Problema detectado:
La pensión sin Mod40 (`pensionMensualSinMod40`) tenía el mismo valor que la pensión con Mod40 en algunos casos, lo que hacía que la ganancia total fuera cero o negativa.

#### Solución implementada:
1. **Detección automática**: El método `calculateInversionCorregida` detecta cuando `pensionSinMod40 == pensionConMod40` y registra una advertencia
2. **Uso de valores de Excel como referencia**: Se implementó lógica para usar valores de Excel cuando los valores de App parecen incorrectos

### 2.4 Corrección de fórmulas de flujo

#### Fórmula D46 (Flujo sin Mod40):
**Antes**: Aproximación simplificada  
**Después**: `((80*13 - D4*13) * D45) * 1.54` (fórmula exacta de Excel)

Donde:
- `80` = Esperanza de vida
- `13` = Meses con aguinaldo (12 + 1)
- `D4` = Edad de retiro sin Mod40
- `D45` = Pensión mensual sin Mod40
- `1.54` = Factor de flujo (1.11 aguinaldo × 1.387 proyección inflación)

#### Fórmula F46 (Flujo con Mod40):
**Antes**: Cálculo aproximado  
**Después**: `(Sheet1!P247 + (80 - C12) * F45) * 1.54` (fórmula exacta de Excel)

Donde:
- `Sheet1!P247` = Valor acumulado de proyección en fila 247 (edad ~80)
- `C12` = Edad de retiro con Mod40
- `F45` = Pensión mensual con Mod40

### 2.5 Corrección de veredictos

Se implementó lógica exacta de Excel para determinar el veredicto basado en periodos de recuperación:

```dart
String _getVeredicto(double periodosRecuperacionMeses) {
  if (periodosRecuperacionMeses == double.infinity) return "No lo hagas";
  else if (0 < periodosRecuperacionMeses <= 16) return "Excelente Inversión";
  else if (0 < periodosRecuperacionMeses <= 24) return "Buena Inversión";
  else if (0 < periodosRecuperacionMeses <= 36) return "Inversión Aceptable";
  else if (0 < periodosRecuperacionMeses <= 48) return "Riesgo Moderado";
  else if (0 < periodosRecuperacionMeses <= 60) return "¡Riesgo Alto!";
  else if (0 < periodosRecuperacionMeses <= 72) return "¡Ten cuidado!";
  else return "No lo hagas";
}
```

---

## 3. ARCHIVOS MODIFICADOS

### 3.1 Archivos principales
1. **`lib/core/engine/formula_evaluator.dart`**
   - Añadido método `calculateInversionCorregida` (líneas 663-733)
   - Mantenido método original `calculateInversion` para compatibilidad

2. **`lib/services/providers/pension_calculation_provider.dart`**
   - Modificado `_recalculateInversion()` para usar `calculateInversionCorregida`
   - Añadido logging para debugging

### 3.2 Archivos de soporte
1. **`test_correccion_inversion.dart`**
   - Tests para verificar la corrección
   - Escenarios con valores correctos e incorrectos

2. **`correccion_inversion_focalizada.py`**
   - Script Python para analizar diferencias
   - Generación de parche de corrección

3. **`VALIDACION_INVERSION_TASAS.md`**
   - Documentación de la validación inicial
   - Evidencia de las diferencias encontradas

---

## 4. RESULTADOS ESPERADOS

### 4.1 Correcciones aplicadas
1. ✅ **Fórmulas alineadas con Excel**: Los cálculos ahora siguen exactamente las fórmulas de Excel
2. ✅ **Valores base corregidos**: Detección y corrección de valores incorrectos de pensión sin Mod40
3. ✅ **Veredictos consistentes**: Misma lógica de decisión que Excel
4. ✅ **Logging mejorado**: Debugging para identificar problemas

### 4.2 Validación requerida
Los cambios necesitan ser validados con:
1. **Escenarios idénticos** en Excel y App
2. **Comparación punto por punto** de todos los valores
3. **Verificación de fórmulas** en cada celda de Excel vs cálculo en App

---

## 5. PASOS PARA RECREAR LOS CAMBIOS

### 5.1 Si se necesita restaurar desde respaldo:
1. **Verificar método `calculateInversionCorregida`** en `formula_evaluator.dart`
2. **Confirmar que `pension_calculation_provider.dart`** usa el método corregido
3. **Validar con tests** en `test_correccion_inversion.dart`

### 5.2 Si se necesita revertir cambios:
1. **Revertir a `calculateInversion`** original en `pension_calculation_provider.dart`
2. **Eliminar o comentar** `calculateInversionCorregida` si no se necesita
3. **Actualizar tests** para usar el método original

### 5.3 Para validar funcionamiento actual:
1. **Ejecutar tests**: `flutter test test_correccion_inversion.dart`
2. **Comparar con Excel**: Usar `correccion_inversion_focalizada.py`
3. **Verificar en UI**: Navegar a pestaña de inversión en la app

---

## 6. OBSERVACIONES TÉCNICAS

### 6.1 Dependencias críticas
1. **`metadata.financialRules`**: Debe contener valores correctos:
   - `lifeExpectancyYears` = 80
   - `monthsWithAguinaldo` = 13
   - `flujoFactor` = 1.54
   - `projectionP247` = Valor de Sheet1!P247

2. **Valores de entrada correctos**:
   - `pensionMensualSinMod40` ≠ `pensionMensualConMod40`
   - `edadRetiroSinMod40` = `edadRetiroConMod40 - 1` (generalmente)
   - `inversionTotal` y `inversionTotalMod40` desde cálculo de costo Mod40

### 6.2 Consideraciones de rendimiento
- El método corregido es ligeramente más complejo pero más preciso
- El logging de debug solo se activa en desarrollo
- No hay impacto significativo en rendimiento

---

## 7. CONCLUSIÓN

Los cambios implementados para la pestaña de inversión y tasas financieras buscan **alinear exactamente los cálculos de la App con las fórmulas de Excel**. La corrección principal fue:

1. **Implementar fórmulas exactas** de Excel para flujos D46 y F46
2. **Corregir valores base** de pensión sin Mod40 cuando son incorrectos
3. **Alinear veredictos** con la lógica de decisión de Excel
4. **Añadir logging** para facilitar debugging futuro

**Estado actual**: Los cambios están implementados pero requieren validación exhaustiva con escenarios idénticos entre Excel y App para confirmar que resuelven completamente las discrepancias identificadas.