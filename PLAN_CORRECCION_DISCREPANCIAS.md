PLAN DE CORRECCIÓN DE DISCREPANCIAS EXCEL vs APP
================================================

ANÁLISIS DE DIFERENCIAS CRÍTICAS
--------------------------------

Basado en la validación completa, estas son las diferencias más significativas:

1. **GANANCIA TOTAL:**
   - Excel: +5,103,567.27 (escenario 1) / +5,553,877.47 (escenario 2)
   - App: -126,626.81 (escenario 1) / -6,464,171.79 (escenario 2)
   - **Diferencia: >100%** (signos opuestos)

2. **TASA DE RENDIMIENTO:**
   - Excel: +17.12% / +18.60%
   - App: -0.27% / -13.54%
   - **Diferencia: >100%** (signos opuestos)

3. **VEREDICTO:**
   - Excel: "Buena Inversión" / "Inversión Aceptable"
   - App: "No lo hagas"
   - **Diferencia: Conclusiones opuestas**

4. **PENSIONES:**
   - Diferencias del 4-46% en pensiones mensuales

CAUSAS PROBABLES IDENTIFICADAS
-------------------------------

1. **FÓRMULAS DIFERENTES:**
   - Excel usa fórmulas específicas en `INVERSION!D49` y `INVERSION!D50`
   - App puede estar usando algoritmos diferentes

2. **DATOS DE ENTRADA DIFERENTES:**
   - Aunque los escenarios son "similares", los inputs exactos pueden diferir
   - Variables como salario_promedio, UMA, semanas_cotizadas pueden variar

3. **FACTORES DE CÁLCULO:**
   - Excel: `=+INVERSION!D49/'COSTO MOD. 40'!G15` (ganancia_total / costo_mod40)
   - App: Puede estar usando diferentes denominadores o factores

4. **LÓGICA DE VEREDICTO:**
   - Excel: Basado en `F9` (periodos de recuperación)
   - App: Basado en tasa_rendimiento negativa

PLAN DE CORRECCIÓN
------------------

**FASE 1: DIAGNÓSTICO PRECISO**
1. Comparar fórmulas exactas de Excel vs algoritmos de App
2. Verificar inputs idénticos (no solo similares)
3. Trazar cálculos paso a paso

**FASE 2: CORRECCIÓN DE FÓRMULAS**
1. Ajustar cálculo de `ganancia_total` en App para coincidir con Excel
2. Corregir fórmula de `tasa_rendimiento` en App
3. Sincronizar lógica de `veredicto`

**FASE 3: VALIDACIÓN**
1. Crear escenarios IDÉNTICOS (mismos inputs exactos)
2. Validar todas las variables nuevamente
3. Asegurar coincidencia >95%

**FASE 4: DOCUMENTACIÓN**
1. Documentar fórmulas corregidas
2. Crear tests automatizados
3. Establecer proceso de validación continua

ACCIONES INMEDIATAS
-------------------

1. **Crear escenarios idénticos:**
   ```python
   # Usar EXACTAMENTE los mismos inputs que Excel
   escenario_identico = {
       "salario_promedio": 2677.3058,
       "uma_diaria": 128.1055,
       "semanas_cotizadas": 2038.14,
       # ... todos los inputs exactos
   }
   ```

2. **Comparar cálculos intermedios:**
   - Flujo sin Mod40 (Excel D46 vs App flujo_sin_mod40)
   - Flujo con Mod40 (Excel F46 vs App flujo_con_mod40)
   - Costo Mod40 (Excel 'COSTO MOD. 40'!G15 vs App inversion_total)

3. **Ajustar App para coincidir con Excel:**
   - Si Excel es la fuente de verdad, la App debe adaptarse
   - Si hay errores en Excel, corregirlos primero

IMPLEMENTACIÓN
--------------

Puedo implementar estas correcciones:
1. Modificar los providers de cálculo en la App (Dart/Flutter)
2. Ajustar las fórmulas en los servicios de cálculo
3. Crear tests de validación cruzada
4. Documentar todos los cambios

¿Quieres que proceda con la implementación de estas correcciones?