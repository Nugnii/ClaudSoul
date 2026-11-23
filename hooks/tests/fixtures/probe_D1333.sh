#!/usr/bin/env bash
# СУДИТ: hooks/completion-gate.sh
# probe_D1333.sh — атаки критиков на `hooks/completion-gate.sh`, отнесённые разбором D1325 к пункту D1333, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1333.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1333
