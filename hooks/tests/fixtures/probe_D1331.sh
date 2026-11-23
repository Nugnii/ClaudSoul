#!/usr/bin/env bash
# СУДИТ: hooks/tool-gate-check.sh
# probe_D1331.sh — атаки критиков на `hooks/tool-gate-check.sh`, отнесённые разбором D1325 к пункту D1331, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1331.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1331
