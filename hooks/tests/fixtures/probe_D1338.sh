#!/usr/bin/env bash
# СУДИТ: scripts/archive-checks-after-commit.sh
# probe_D1338.sh — атаки критиков на `scripts/archive-checks-after-commit.sh`, отнесённые разбором D1325 к пункту D1338, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1338.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1338
