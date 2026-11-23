#!/usr/bin/env bash
# СУДИТ: hooks/command-scope-lib.sh
# probe_D1326.sh — атаки критиков на `hooks/command-scope-lib.sh`, отнесённые разбором D1325 к пункту D1326, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1326.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1326
