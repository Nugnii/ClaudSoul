#!/usr/bin/env bash
# СУДИТ: hooks/intrusiveness-tracker.sh
# probe_D1335.sh — атаки критиков на `hooks/intrusiveness-tracker.sh`, отнесённые разбором D1325 к пункту D1335, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1335.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1335
