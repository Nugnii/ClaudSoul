#!/usr/bin/env bash
# СУДИТ: hooks/session-collector.sh
# probe_D1334.sh — атаки критиков на `hooks/session-collector.sh`, отнесённые разбором D1325 к пункту D1334, зелёны.
# Проверка результата: bash hooks/tests/fixtures/probe_D1334.sh → 0 — зелёны все; 1 — есть красная; 2 — не измерено (нет архива атак).
exec bash "$(dirname "$0")/probe_attacks.sh" D1334
