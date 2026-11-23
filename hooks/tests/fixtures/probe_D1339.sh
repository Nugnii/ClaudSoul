#!/usr/bin/env bash
# СУДИТ: scripts/dep-index.py
# probe_D1339.sh — атаки критиков на `scripts/dep-index.py`, отнесённые разбором D1325 к пункту D1339, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1339.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1339
