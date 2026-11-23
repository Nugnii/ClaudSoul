#!/usr/bin/env bash
# СУДИТ: scripts/docs-refresh-claims.sh
# probe_D1336.sh — атаки критиков на `scripts/docs-refresh-claims.sh`, отнесённые разбором D1325 к пункту D1336, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1336.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1336
