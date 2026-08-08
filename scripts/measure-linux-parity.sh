#!/usr/bin/env bash
# measure-linux-parity.sh — проходит ли набор на машине БЕЗ установленного ClaudSoul.
#
# Отдельным скриптом, потому что у замера должен быть исполнимый вид: строка в реестре
# `scripts/measurements.tsv` обязана указывать на команду, а не на инструкцию в документации.
# Рецепт тот же, что записан в docs/development.md; здесь он оформлен так, чтобы его мог
# запустить планировщик, а не только человек.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
command -v docker >/dev/null 2>&1 || { echo "measure-linux-parity: docker недоступен — замер пропущен"; exit 0; }
docker info >/dev/null 2>&1 || { echo "measure-linux-parity: демон docker не запущен — замер пропущен"; exit 0; }
cd "$REPO" || exit 2
docker run --rm -v "$PWD":/repo:ro -w /repo debian:stable-slim bash -c '
  apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq jq git python3 >/dev/null 2>&1
  cp -R /repo /work; cd /work/hooks/tests && bash run_all.sh 2>&1 | tail -2'
