#!/usr/bin/env bash
# СУДИТ: scripts/project-graph.py
# probe_D1340.sh — атаки критиков на `scripts/project-graph.py`, отнесённые разбором D1325 к пункту D1340, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1340.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1340
