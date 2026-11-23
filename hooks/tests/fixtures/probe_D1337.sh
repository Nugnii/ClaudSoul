#!/usr/bin/env bash
# СУДИТ: scripts/root-map.py
# probe_D1337.sh — атаки критиков на `scripts/root-map.py`, отнесённые разбором D1325 к пункту D1337, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1337.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1337
