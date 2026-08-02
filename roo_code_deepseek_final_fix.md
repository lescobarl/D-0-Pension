# Fix final para tu configuración de Deep Seek en Roo Code

Basado en tu captura de pantalla, estos son los pasos EXACTOS para solucionar el error 400:

---

## 🚨 Problema principal detectado en tu configuración
**Falta la URL base de la API** y estás usando el modelo incorrecto para desarrollo de código:

### 1. Agrega la URL base de la API
En el campo **`Api Base`** (que está vacío en tu captura) escribe:
```
https://api.deepseek.com/v1
```

### 2. Actualiza el modelo para desarrollo de código
Actualmente tienes `deepseek-chat` (para chat general). Para programación usa:
```
deepseek-coder-v2
```

O si prefieres el modelo de chat oficial:
```
deepseek-chat
```

---

## 📌 Pasos finales
1. Haz clic en **`Save`** en la esquina superior derecha de la pantalla de configuración
2. Reinicia VS Code completamente
3. Prueba a usar el asistente de Roo Code nuevamente

---

## 🧪 Prueba rápida para confirmar
Si sigues teniendo errores, ejecuta este comando en tu terminal:
```bash
curl https://api.deepseek.com/v1/chat/completions \
  -H "Authorization: Bearer TU_CLAVE_DEEPSEEK" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-coder-v2",
    "messages": [{"role": "user", "content": "Hola, prueba de código"}]
  }'
```

Si obtienes una respuesta válida, el problema está resuelto. Si no, revisa:
- Que tu clave API de Deep Seek sea válida (obténla en https://platform.deepseek.com/)
- Que tu cuenta de Deep Seek tenga billing habilitado
- Que no tengas espacios o caracteres extraños en tu clave API