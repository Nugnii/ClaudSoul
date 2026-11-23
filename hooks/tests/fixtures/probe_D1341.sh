#!/usr/bin/env bash
# СУДИТ: scripts/named-limits.py
# probe_D1341.sh — атаки критиков на `scripts/named-limits.py`, отнесённые разбором D1325 к пункту D1341, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1341.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1341
