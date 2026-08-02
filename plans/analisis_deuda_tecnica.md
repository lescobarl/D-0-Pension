# Análisis de Deuda Técnica - Calculadora de Pensión

## Resumen Técnico
**Fecha**: 27 de julio de 2026  
**Base de código**: 157 archivos Dart, ~30,000 líneas de código  
**Arquitectura**: Flutter + Provider + MVVM  
**Estado**: Funcional pero con oportunidades de mejora significativas

## 1. Deuda Arquitectónica Crítica

### 1.1 Violación de Principio de Responsabilidad Única
**Archivo**: `lib/services/retroactive_provider.dart` (1408 líneas)
**Problemas**:
- Maneja UI state, cálculos, persistencia y lógica de negocio
- 6 cálculos diferentes en un solo archivo
- Alto acoplamiento entre módulos
- Dificultad para testear

**Recomendación**: Refactorizar en 4 providers:
```dart
// Nueva estructura
lib/services/
├── providers/
│   ├── pension_provider.dart        // Cálculos de pensión base
│   ├── mod40_provider.dart          // Modalidad 40 específico
│   ├── retroactive_provider.dart    // Pago retroactivo (reducido)
│   └── user_input_provider.dart     // Inputs y validación
└── engine/                          // Lógica pura de cálculo
```

### 1.2 Gestión de Estado Ineficiente
**Problema**: `notifyListeners()` se llama excesivamente
**Ejemplo**: Cada setter llama `notifyListeners()` incluso cuando no hay cambios visibles
**Impacto**: Rebuilds innecesarios, performance reducida

**Solución**: Implementar `ChangeNotifier` optimizado o migrar a Riverpod
```dart
// Patrón recomendado
class OptimizedProvider extends ChangeNotifier {
  void setValue(T newValue) {
    if (_value == newValue) return; // Early return
    _value = newValue;
    // Solo notificar si afecta UI
    if (_shouldNotifyUI) {
      notifyListeners();
    }
  }
}
```

### 1.3 Falta de Abstracción en Cálculos
**Problema**: `FormulaEvaluator` (1162 líneas) es un "God Class"
**Recomendación**: Patrón Strategy para fórmulas
```dart
abstract class PensionFormula {
  double calculate(PensionContext context);
}

class FactAsigFormula implements PensionFormula { ... }
class Mod40Formula implements PensionFormula { ... }
```

## 2. Deuda de Calidad de Código

### 2.1 Código Duplicado
**Ejemplos encontrados**:
- Validación de fechas repetida en múltiples widgets
- Formateo de números en varios lugares
- Cálculos de UMA/SM duplicados

**Recomendación**: Extraer a utilities comunes
```dart
lib/core/utils/
├── date_validator.dart
├── number_formatter.dart
├── uma_calculator.dart
└── pension_validator.dart
```

### 2.2 Manejo de Errores Básico
**Problema**: Excepciones no manejadas, falta de logging estructurado
**Solución**:
```dart
// Implementar error handling centralizado
class ErrorHandler {
  static void logError(dynamic error, StackTrace stack) {
    // Log estructurado
    // Reporte a analytics
    // Recovery automático cuando sea posible
  }
}
```

### 2.3 Falta de Inmutabilidad
**Problema**: Muchas variables mutables, estado compartido
**Recomendación**: Usar `final` donde sea posible, patrones de inmutabilidad
```dart
class PensionCalculation {
  final double amount;
  final DateTime date;
  
  const PensionCalculation({required this.amount, required this.date});
  
  PensionCalculation copyWith({double? amount, DateTime? date}) {
    return PensionCalculation(
      amount: amount ?? this.amount,
      date: date ?? this.date,
    );
  }
}
```

## 3. Deuda de Testing

### 3.1 Cobertura Desigual
**Estadísticas**:
- Tests unitarios: ~40% cobertura
- Tests de widget: ~20% cobertura
- Tests de integración: ~10% cobertura

**Áreas críticas sin tests**:
- Persistencia de datos
- Cálculos complejos de Modalidad 40
- Flujos de UI completos

### 3.2 Tests Frágiles
**Problema**: Tests dependen de datos reales de Excel
**Solución**: Mock de `FormulaEvaluator` y datos de prueba
```dart
// Test más robusto
test('FactAsig calculation with mocked data', () {
  final mockEvaluator = MockFormulaEvaluator();
  when(mockEvaluator.calculateFactAsig(any))
      .thenReturn(FactAsigCalculation(...));
  
  // Test con datos controlados
});
```

## 4. Deuda de Performance

### 4.1 Recalculaciones Costosas
**Problema**: Cada cambio recalcula 6 módulos completos
**Optimización**: Cálculos diferidos y cache
```dart
class CalculationCache {
  final Map<String, dynamic> _cache = {};
  
  T getOrCalculate<T>(String key, T Function() calculate) {
    if (_cache.containsKey(key)) {
      return _cache[key] as T;
    }
    final result = calculate();
    _cache[key] = result;
    return result;
  }
}
```

### 4.2 Widgets No Optimizados
**Problema**: Falta de `const`, `AutomaticKeepAliveClientMixin`
**Recomendación**: Audit de widgets y optimización
```dart
// Widgets que deberían ser const
class PensionCard extends StatelessWidget {
  const PensionCard({super.key, required this.data});
  
  @override
  Widget build(BuildContext context) {
    return const Card(...); // Más const
  }
}
```

## 5. Deuda de Seguridad

### 5.1 Datos Sensibles en Persistencia
**Problema**: `SharedPreferences` sin encriptación
**Solución**: Encriptación con `flutter_secure_storage` para datos sensibles
```dart
class SecurePersistence {
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  
  Future<void> saveSensitiveData(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }
}
```

### 5.2 Validación de Inputs Insuficiente
**Problema**: Inputs no sanitizados contra inyección
**Solución**: Validación exhaustiva
```dart
class InputValidator {
  static bool isValidSalary(String input) {
    final parsed = double.tryParse(input);
    return parsed != null && parsed > 0 && parsed < 1000000;
  }
}
```

## 6. Deuda de Mantenibilidad

### 6.1 Documentación Insuficiente
**Problema**: Comentarios mínimos, falta de documentación de API
**Solución**: 
- Implementar `dartdoc` con ejemplos
- Documentar interfaces públicas
- Guías de contribución

### 6.2 Configuración Hardcodeada
**Problema**: Valores mágicos en código
```dart
// MAL
if (semanas > 250) { ... }

// BIEN
static const int MAX_SEMANAS = 250;
if (semanas > PensionConstants.MAX_SEMANAS) { ... }
```

## 7. Priorización de Deuda

### Crítica (Resolver en 2 semanas)
1. Bug de salario registrado (25 × UMA)
2. Bugs de fechas (UI bloqueada)
3. Refactorización inicial de `retroactive_provider.dart`

### Alta (Resolver en 1 mes)
1. Implementar error handling centralizado
2. Extraer código duplicado a utilities
3. Mejorar cobertura de tests (>70%)

### Media (Resolver en 3 meses)
1. Migración a Riverpod para mejor gestión de estado
2. Implementar cálculo cache
3. Optimización de widgets con `const`

### Baja (Resolver en 6 meses)
1. Internacionalización completa
2. Analytics y monitoring
3. Refactorización completa a Clean Architecture

## 8. Métricas de Mejora

### Objetivos Cuantitativos:
- **Complexidad ciclomática**: Reducir de 15 a <10 promedio
- **Líneas por archivo**: Reducir de 1408 a <500 en provider principal
- **Cobertura de tests**: Aumentar de 40% a >90%
- **Tiempo de build**: Reducir en 30%
- **Tamaño de APK**: Mantener o reducir

### Objetivos Cualitativos:
- **Mantenibilidad**: Score >80 en análisis estático
- **Documentación**: 100% de APIs públicas documentadas
- **Onboarding**: Nuevo desarrollador productivo en <2 días

## 9. Plan de Acción Inmediato

### Semana 1:
1. Crear `PensionConstants` con valores mágicos
2. Extraer `DateValidator` y `NumberFormatter`
3. Implementar cálculo automático de salario registrado

### Semana 2:
1. Dividir `retroactive_provider.dart` en 2-3 providers más pequeños
2. Implementar `ErrorHandler` centralizado
3. Agregar tests para nuevas utilidades

### Semana 3-4:
1. Implementar cálculo cache
2. Optimizar widgets con `const`
3. Agregar logging estructurado

## 10. Conclusión

La deuda técnica actual es manejable pero requiere atención proactiva. Las mejoras propuestas no solo reducirán bugs sino que también:

1. **Acelerarán desarrollo futuro**: Código más modular = nuevas features más rápidas
2. **Mejorarán performance**: Cálculos optimizados = mejor experiencia de usuario
3. **Reducirán costos de mantenimiento**: Menos bugs = menos tiempo en soporte
4. **Facilitarán onboarding**: Código más claro = nuevos desarrolladores más productivos

**Recomendación**: Iniciar con las correcciones críticas y seguir un roadmap incremental para evitar interrupciones en el desarrollo actual.