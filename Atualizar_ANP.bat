@echo off
chcp 65001 >nul
title Atualizando App ANP - Royal FIC
echo ============================================
echo   ATUALIZACAO APP ANP - ROYAL FIC
echo ============================================
echo.
powershell.exe -ExecutionPolicy Bypass -File "%~dp0atualizar_anp.ps1"
echo.
echo ============================================
echo   CONCLUIDO! Pressione qualquer tecla...
echo ============================================
pause >nul
