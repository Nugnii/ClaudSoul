#!/usr/bin/env bash
# СУДИТ: hooks/hook-input-lib.sh
# probe_D1328.sh — атаки критиков на `hooks/hook-input-lib.sh`, отнесённые разбором D1325 к пункту D1328, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1328.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1328
