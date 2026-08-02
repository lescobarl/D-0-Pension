# Solución al error 400 al usar Deep Seek via OpenRouter en Roo Code

## Paso 1: Verifica tu clave API
Asegúrate de usar una clave de **OpenRouter** (empieza con `sk-or-v1-`), no una clave de Deep Seek directamente. Puedes obtenerla en: https://openrouter.ai/keys

## Paso 2: Usa el identificador correcto del modelo
Los modelos de Deep Seek en OpenRouter requieren el ID completo del modelo:
- Para desarrollo de código: `deepseek-ai/deepseek-coder-v2` (recomendado)
- Versión económica: `deepseek-ai/deepseek-llm-7b-chat`
- Versión premium: `deepseek-ai/deepseek-llm-67b-chat`

## Paso 3: Configura Roo Code correctamente
1. Abre la configuración de VS Code: `Ctrl + ,` (Windows/Linux) o `Cmd + ,` (Mac)
2. Busca y configura estos parámetros:
   - **`Roo Code: Api Key`**: Pegar tu clave de OpenRouter (`sk-or-v1-...`)
   - **`Roo Code: Model`**: Ingresar el ID completo del modelo (ej: `deepseek-ai/deepseek-coder-v2`)
   - **`Roo Code: Api Base`**: Dejar el valor predeterminado de OpenRouter: `https://openrouter.ai/api/v1`
3. Reinicia VS Code para aplicar los cambios.

## Paso 4: Prueba la API directamente
Ejecuta este comando en tu terminal para confirmar que tu clave y modelo funcionan:
```bash
curl https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer TU_CLAVE_OPENROUTER" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ai/deepseek-coder-v2",
    "messages": [{"role": "user", "content": "Prueba de API"}]
  }'
```

## Paso 5: Verifica los límites de tu plan
Algunos modelos de Deep Seek en OpenRouter requieren un plan de pago. Revisa la página del modelo en https://openrouter.ai/models para confirmar el acceso.

## Paso 6: Actualiza Roo Code
Asegúrate de tener la última versión de la extensión Roo Code para evitar errores de configuración con modelos personalizados.

## Si usas Deep Seek directamente (sin OpenRouter)
1. Obtén una clave de Deep Seek en: https://platform.deepseek.com/
2. Configura Roo Code:
   - **`Roo Code: Api Base`**: `https://api.deepseek.com/v1`
   - **`Roo Code: Api Key`**: Tu clave de Deep Seek
   - **`Roo Code: Model`**: `deepseek-coder`
3. Reinicia VS Code.