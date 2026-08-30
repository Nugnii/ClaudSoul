"""JSON Schemas for Extract output (entity/fact/relation + envelope).

Usage:
    from ingest.schemas import validate_extract_output
    validate_extract_output(data)  # raises jsonschema.ValidationError on failure
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

_DIR = Path(__file__).parent
_SCHEMA_FILES = {
    "entity": "entity.json",
    "fact": "fact.json",
    "relation": "relation.json",
    "extract_output": "extract_output.json",
}


def load(name: str) -> dict:
    return json.loads((_DIR / _SCHEMA_FILES[name]).read_text(encoding="utf-8"))


@lru_cache(maxsize=1)
def _validator():
    from jsonschema import Draft202012Validator
    from referencing import Registry, Resource

    resources = [
        (load(name)["$id"], Resource.from_contents(load(name)))
        for name in _SCHEMA_FILES
    ]
    registry = Registry().with_resources(resources)
    return Draft202012Validator(load("extract_output"), registry=registry)


def validate_extract_output(data: dict) -> None:
    """Raises jsonschema.ValidationError if data doesn't match the envelope schema."""
    _validator().validate(data)
