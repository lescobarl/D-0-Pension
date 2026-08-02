# Solución al error 400 al usar Deep Seek DIRECTAMENTE en Roo Code

Basado en la captura de pantalla que compartiste, aquí están los pasos para solucionar el error 400:

---

## 🚨 Errores comunes y soluciones

### 1. **URL base de la API incorrecta**
En la configuración de Roo Code, la URL base para Deep Seek DIRECTO es: 
`https://api.deepseek.com/v1`

> Si tenías configurada la URL de OpenRouter antes, eso es el problema principal! Cambia la URL base a la de Deep Seek.

### 2. **Clave API inválida**
Tu clave de Deep Seek debe ser obtenida en: https://platform.deepseek.com/ 
- Asegúrate de que la clave no tenga espacios ni caracteres extraños
- Verifica que tu cuenta de Deep Seek tenga saldo disponible o billing habilitado

### 3. **Modelo incorrecto**
En la captura tienes `deepseek-chat`, que es válido para chat general, pero para desarrollo de código usa:
- `deepseek-coder-v2` (recomendado para programación)
- `deepseek-coder` (versión anterior)
- `deepseek-chat` (para chat general)

### 4. **Prueba la API directamente**
Ejecuta este comando en tu terminal para confirmar que tu clave y modelo funcionan:
```bash
curl https://api.deepseek.com/v1/chat/completions \
  -H "Authorization: Bearer TU_CLAVE_DEEPSEEK" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-coder-v2",
    "messages": [{"role": "user", "content": "Prueba de API de Deep Seek"}]
  }'
```

### 5. **Configura Roo Code correctamente**
Basado en tu captura de pantalla:
1. Abre la configuración de VS Code: `Ctrl + ,`
2. Busca **`Roo Code: Api Base`** y configúrala en: `https://api.deepseek.com/v1`
3. Verifica que **`Roo Code: Api Key`** sea tu clave válida de Deep Seek
4. Actualiza **`Roo Code: Model`** al modelo que necesites (ej: `deepseek-coder-v2`)
5. Reinicia VS Code

---

## 📌 Configuración exacta de tu captura
Lo que debes ver en la pantalla de configuración:
- **API Provider**: `DeepSeek`
- **DeepSeek API Key**: `tu-clave-de-deep-seek-aqui`
- **Model**: `deepseek-coder-v2` (o el que prefieras)
- **Api Base**: `https://api.deepseek.com/v1`

---

## 📝 Notas importantes
- Los modelos de Deep Seek requieren que tu cuenta tenga billing habilitado (no hay opción gratuita oficial)
- Si sigues teniendo error 400, revisa el panel de tu cuenta de Deep Seek para ver si hay errores de autenticación
- Actualiza la extensión de Roo Code a la última versión para evitar errores de compatibilidad