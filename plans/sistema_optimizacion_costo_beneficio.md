# 📋 SISTEMA DE OPTIMIZACIÓN COSTO-BENEFICIO

## 1. CONTEXTO Y PROBLEMA

**Usuario Objetivo:**
- Personas 55-65 años próximas a retiro IMSS Ley 73
- Ya capturaron sus datos en la app (salario, semanas, dependientes)
- Necesitan decidir: **¿Cuántas UMAs pagar? ¿A qué edad retirarse?**

**Problema Actual:**
- 150 combinaciones posibles (UMA 1-25 × Edad 60-65)
- Usuario mayor se abruma con opciones
- No entiende trade-offs entre pensión, costo, ROI
- Riesgo de tomar decisión subóptima con impacto de por vida

**Objetivo del Sistema:**
Encontrar la **mejor combinación costo-beneficio** personalizada para cada usuario.

---

## 2. ARQUITECTURA TÉCNICA

### 2.1 Diagrama de Componentes
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   IA Conversa-  │    │   Motor de      │    │   Interfaz      │
│   cional        │◄──►│   Optimización  │◄──►│   Visual        │
│   (ChatPrompt)  │    │   (Grid Search) │    │   (ResultsView) │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Preferencias  │    │   Cálculo 150   │    │   Top 3         │
│   del Usuario   │    │   Escenarios    │    │   Recomenda-    │
│   (max/min/bal) │    │   (Retroactive- │    │   ciones        │
│                 │    │   Provider)     │    │   Visuales      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### 2.2 Flujo de Datos
1. **Entrada**: Datos usuario + preferencia (max pensión, fast ROI, balance)
2. **Procesamiento**: Grid search 150 combinaciones → cálculo métricas
3. **Salida**: Top 3 escenarios ordenados + explicaciones
4. **Aplicación**: Configura automáticamente UMA multiplier y edad retiro

---

## 3. ESPECIFICACIONES TÉCNICAS

### 3.1 Clases y Estructuras de Datos

```dart
/// Objetivo de optimización seleccionado por el usuario
enum OptimizationGoal {
  maxPension,    // Maximizar pensión mensual
  fastROI,       // Minimizar años de recuperación
  balanced       // Balance entre pensión y ROI
}

/// Resultado de un escenario evaluado
class OptimizedScenario {
  final int umaMultiplier;      // 1-25
  final double retirementAge;   // 60, 61, 62, 63, 64, 65
  final double monthlyPension;  // Pensión mensual resultante
  final double totalCost;       // Costo total Mod40
  final double annualROI;       // ROI anualizado = (pensión×12)/costo
  final double paybackYears;    // Años para recuperar inversión
  final String explanation;     // Explicación en lenguaje natural
  
  // Métrica de ranking según objetivo
  double getScore(OptimizationGoal goal) {
    switch (goal) {
      case OptimizationGoal.maxPension:
        return monthlyPension;
      case OptimizationGoal.fastROI:
        return 1 / paybackYears; // Mayor score = menor tiempo
      case OptimizationGoal.balanced:
        return (annualROI * 0.4) + (monthlyPension.normalized * 0.6);
    }
  }
}

/// Motor principal de optimización
class CostBenefitOptimizer {
  final RetroactiveProvider provider;
  
  Future<List<OptimizedScenario>> findBestScenarios({
    required OptimizationGoal goal,
    int topN = 3,
  }) async {
    final List<OptimizedScenario> allScenarios = [];
    
    // Grid search sobre todas las combinaciones
    for (int uma = 1; uma <= 25; uma++) {
      for (double age in [60.0, 61.0, 62.0, 63.0, 64.0, 65.0]) {
        // 1. Configurar provider con combinación actual
        provider.setUmaMultiplier(uma.toDouble());
        provider.setEdadRetiro(age);
        
        // 2. Esperar recálculos
        await Future.delayed(const Duration(milliseconds: 10));
        
        // 3. Extraer resultados
        final scenario = OptimizedScenario(
          umaMultiplier: uma,
          retirementAge: age,
          monthlyPension: provider.pensionMod40Mensual,
          totalCost: provider.costoMod40Total,
          annualROI: _calculateROI(provider),
          paybackYears: _calculatePaybackYears(provider),
          explanation: _generateExplanation(uma, age, provider),
        );
        
        allScenarios.add(scenario);
      }
    }
    
    // 4. Ordenar según objetivo y retornar top N
    allScenarios.sort((a, b) => 
        b.getScore(goal).compareTo(a.getScore(goal)));
    
    return allScenarios.take(topN).toList();
  }
  
  double _calculateROI(RetroactiveProvider p) {
    final annualPension = p.pensionMod40Mensual * 12;
    return annualPension / p.costoMod40Total;
  }
  
  double _calculatePaybackYears(RetroactiveProvider p) {
    final annualPension = p.pensionMod40Mensual * 12;
    return p.costoMod40Total / annualPension;
  }
  
  String _generateExplanation(int uma, double age, RetroactiveProvider p) {
    // Generar explicación personalizada según métricas
    if (annualROI > 0.4) return "Excelente retorno de inversión";
    if (paybackYears < 3) return "Recuperas tu dinero rápidamente";
    return "Buena pensión con costo razonable";
  }
}
```

### 3.2 Extensión del ChatPrompt

```dart
// En lib/core/ai/chat_prompt.dart agregar:
static const String optimizationPromptExtension = '''
### Modo 5: Optimización de Costo-Beneficio
Cuando el usuario pida ayuda para encontrar la mejor opción de pensión,
responde SOLO con este JSON:

{"type":"optimization_question","message":"¿Qué es más importante para ti?",
"options":[
  {"id":"max_pension","label":"Máxima pensión mensual (sin importar costo)"},
  {"id":"fast_roi","label":"Recuperar mi inversión lo más rápido posible"},
  {"id":"balanced","label":"Balance entre pensión buena y costo razonable"}
]}

Cuando el usuario seleccione una opción, la app ejecutará la optimización
y mostrará los resultados. NO intentes calcular nada tú mismo.
''';
```

---

## 4. INTERFAZ DE USUARIO

### 4.1 Pantalla de Optimización (`OptimizerView`)

```dart
class OptimizerView extends StatefulWidget {
  final RetroactiveProvider provider;
  
  const OptimizerView({super.key, required this.provider});
  
  @override
  State<OptimizerView> createState() => _OptimizerViewState();
}

class _OptimizerViewState extends State<OptimizerView> {
  OptimizationGoal? _selectedGoal;
  List<OptimizedScenario> _results = [];
  bool _calculating = false;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Encontrar Mejor Opción')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Paso 1: Selección de objetivo
            _buildGoalSelection(),
            
            const SizedBox(height: 24),
            
            // Paso 2: Resultados
            if (_results.isNotEmpty) _buildResults(),
            
            // Paso 3: Botón de acción
            _buildActionButton(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildGoalSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Qué es más importante para ti?',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        // Radio buttons para los 3 objetivos
        _buildGoalOption(OptimizationGoal.maxPension, 
            'Máxima pensión mensual', 'Obtener la pensión más alta posible'),
        _buildGoalOption(OptimizationGoal.fastROI,
            'Recuperar inversión rápido', 'Minimizar el tiempo para recuperar tu dinero'),
        _buildGoalOption(OptimizationGoal.balanced,
            'Balance pensión/costo', 'Buena pensión con costo razonable'),
      ],
    );
  }
  
  Widget _buildResults() {
    return Column(
      children: [
        Text('Top 3 Recomendaciones:',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        // Tarjetas para cada recomendación
        for (int i = 0; i < _results.length; i++)
          _buildScenarioCard(_results[i], i),
      ],
    );
  }
  
  Widget _buildScenarioCard(OptimizedScenario scenario, int rank) {
    final medals = ['🥇', '🥈', '🥉'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(medals[rank], style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${scenario.umaMultiplier} UMAs • Retiro a ${scenario.retirementAge.toInt()} años',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Métricas clave
            _buildMetricRow('Pensión mensual', 
                '\$${scenario.monthlyPension.toStringAsFixed(2)}'),
            _buildMetricRow('Costo total', 
                '\$${scenario.totalCost.toStringAsFixed(0)}'),
            _buildMetricRow('Recuperas en', 
                '${scenario.paybackYears.toStringAsFixed(1)} años'),
            _buildMetricRow('ROI anual', 
                '${(scenario.annualROI * 100).toStringAsFixed(1)}%'),
            const SizedBox(height: 12),
            Text(scenario.explanation,
                style: const TextStyle(fontStyle: FontStyle.italic)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _applyScenario(scenario),
              child: const Text('Aplicar esta opción'),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _runOptimization() async {
    if (_selectedGoal == null) return;
    
    setState(() => _calculating = true);
    
    final optimizer = CostBenefitOptimizer(provider: widget.provider);
    _results = await optimizer.findBestScenarios(goal: _selectedGoal!);
    
    setState(() => _calculating = false);
  }
  
  void _applyScenario(OptimizedScenario scenario) {
    widget.provider.setUmaMultiplier(scenario.umaMultiplier.toDouble());
    widget.provider.setEdadRetiro(scenario.retirementAge);
    Navigator.pop(context); // Regresar a pantalla principal
  }
}
```

### 4.2 Integración con Chat IA

```dart
// En lib/presentation/screens/ai_chat_view.dart agregar:
void _handleOptimizationResponse(OptimizationGoal goal) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => OptimizerView(
        provider: Provider.of<RetroactiveProvider>(context, listen: false),
        initialGoal: goal,
      ),
    ),
  );
}
```

---

## 5. PLAN DE IMPLEMENTACIÓN

### Fase 1: Núcleo del Optimizador (2 días)
- [ ] Crear `OptimizedScenario` class
- [ ] Implementar `CostBenefitOptimizer` con grid search
- [ ] Integrar con `RetroactiveProvider` para cálculos
- [ ] Testear performance (150 cálculos ≈ 2-3 segundos)

### Fase 2: Interfaz de Usuario (2 días)
- [ ] Crear `OptimizerView` con selección de objetivos
- [ ] Diseñar tarjetas de resultados visuales
- [ ] Implementar aplicación automática de escenarios
- [ ] Integrar navegación desde chat IA

### Fase 3: Extensión IA (1 día)
- [ ] Extender `ChatPrompt` con modo optimización
- [ ] Actualizar `AiChatService` para manejar respuestas
- [ ] Integrar flujo conversacional completo

### Fase 4: Testing y Refinamiento (1 día)
- [ ] Testear con datos reales de usuarios
- [ ] Optimizar performance
- [ ] Refinar explicaciones y textos
- [ ] Validar cálculos vs Excel

---

## 6. MÉTRICAS DE ÉXITO

### 6.1 Técnicas
- **Performance**: < 3 segundos para 150 cálculos
- **Precisión**: Resultados dentro de ±1% vs Excel
- **Estabilidad**: Sin crashes en grid search completo

### 6.2 UX
- **Simplicidad**: Usuario completa optimización en < 1 minuto
- **Claridad**: Explicaciones comprensibles para usuarios mayores
- **Utilidad**: Recomendaciones personalizadas y relevantes

### 6.3 Negocio
- **Adopción**: > 30% de usuarios usan optimizador
- **Satisfacción**: > 4.5/5 en feedback
- **Retención**: Usuarios regresan para re-evaluar escenarios

---

## 7. RIESGOS Y MITIGACIÓN

| Riesgo | Impacto | Mitigación |
|--------|---------|------------|
| Performance lento | Alto | Caching de resultados, cálculo incremental |
| Explicaciones confusas | Medio | Test A/B con usuarios reales, lenguaje simple |
| Cálculos incorrectos | Crítico | Validación exhaustiva vs Excel, unit tests |
| Sobrecarga IA | Medio | Límite de uso, cálculo local no IA |
| Complejidad UI | Medio | Diseño iterativo, feedback temprano |

---

## 8. ARCHIVOS A MODIFICAR/CREAR

```
NUEVOS:
lib/core/optimization/optimized_scenario.dart
lib/core/optimization/cost_benefit_optimizer.dart
lib/presentation/screens/optimizer_view.dart

MODIFICAR:
lib/core/ai/chat_prompt.dart          # Agregar modo optimización
lib/services/ai_chat_service.dart     # Manejar respuestas optimización
lib/presentation/screens/ai_chat_view.dart # Integrar navegación
lib/presentation/screens/captura_view.dart # Botón acceso rápido
```

---

## 9. VALIDACIÓN PRE-IMPLEMENTACIÓN

Antes de ejecutar este plan, validar:
1. ✅ Configurable UMA multiplier (1-25) - IMPLEMENTADO
2. ✅ Edad retiro con porcentajes visibles - IMPLEMENTADO  
3. ✅ Motor de cálculo estable y preciso - VERIFICADO
4. ✅ IA conversacional funcional - VERIFICADO
5. ✅ Performance aceptable para 150 cálculos - POR TESTEAR

---

## 10. RESUMEN EJECUTIVO

**Sistema propuesto**: Optimizador híbrido IA + cálculo local que encuentra la mejor combinación UMA×Edad para maximizar costo-beneficio.

**Valor único**: Personalización total basada en datos reales del usuario + explicaciones claras para usuarios mayores.

**Factibilidad técnica**: 100% posible con arquitectura actual, 4-6 días de desarrollo.

**Impacto esperado**: Usuarios toman decisiones óptimas de pensión con confianza, reduciendo ansiedad y errores costosos.