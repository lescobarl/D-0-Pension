@echo off
echo Iniciando servidor web en puerto 8082...
start /B python -m http.server 8082
timeout /t 2 /nobreak >nul
echo Abriendo Chrome en http://localhost:8082/temp_web_index.html...
start chrome http://localhost:8082/temp_web_index.html
echo Servidor web ejecutándose. Presiona Ctrl+C para detener.