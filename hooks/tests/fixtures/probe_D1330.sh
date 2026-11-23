#!/usr/bin/env bash
# СУДИТ: hooks/rework-detector.sh
# probe_D1330.sh — атаки критиков на `hooks/rework-detector.sh`, отнесённые разбором D1325 к пункту D1330, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1330.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1330
