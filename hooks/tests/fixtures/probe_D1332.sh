#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh
# probe_D1332.sh — атаки критиков на `hooks/backlog-lib.sh`, отнесённые разбором D1325 к пункту D1332, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1332.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1332
