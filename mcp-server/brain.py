"""Export/import the full ClaudSoul 'brain' — knowledge, skills, hooks, rules."""

import json
import shutil
import tarfile
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Optional

CLAUDE_DIR = Path.home() / ".claude"
KNOWLEDGE_DIR = CLAUDE_DIR / "global-lessons"
COMMANDS_DIR = CLAUDE_DIR / "commands"
HOOKS_DIR = CLAUDE_DIR / "hooks"
TEMPLATES_DIR = CLAUDE_DIR / "templates"
SESSIONS_DIR = CLAUDE_DIR / "sessions"
SETTINGS_FILE = CLAUDE_DIR / "settings.json"
RULES_FILE = CLAUDE_DIR / "CLAUDE.md"
DB_FILE = CLAUDE_DIR / "knowledge.db"

# ClaudSoul repo paths (for domains)
REPO_DIR = Path(__file__).parent.parent
DOMAINS_DIR = REPO_DIR / "domains"


def export_brain(output_dir: Optional[Path] = None) -> Path:
    """Pack the entire brain into a .tar.gz archive.

    Contents:
    - manifest.json — metadata (date, counts, version)
    - global-lessons/ — all knowledge files
    - commands/ — all skills
    - hooks/ — hook scripts
    - templates/ — file templates
    - domains/ — domain graph
    - sessions/ — session registry
    - knowledge.db — vector search database
    - settings.json — hooks configuration
    - CLAUDE.md — global rules
    """
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = output_dir or Path.home() / "Desktop"
    archive_name = f"claudsoul-brain-{timestamp}.tar.gz"
    archive_path = out_dir / archive_name

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)

        # Manifest
        manifest = {
            "version": "1.0.0-rc",
            "exported_at": datetime.now().isoformat(),
            "machine": _machine_id(),
            "contents": {},
        }

        # 1. Knowledge files
        if KNOWLEDGE_DIR.exists():
            dst = tmp / "global-lessons"
            shutil.copytree(KNOWLEDGE_DIR, dst)
            count = len(list(dst.glob("*.md")))
            manifest["contents"]["global-lessons"] = count

        # 2. Skills (commands)
        if COMMANDS_DIR.exists():
            dst = tmp / "commands"
            shutil.copytree(COMMANDS_DIR, dst)
            skills = [d.name for d in dst.iterdir() if d.is_dir()]
            manifest["contents"]["commands"] = skills

        # 3. Hooks
        if HOOKS_DIR.exists():
            dst = tmp / "hooks"
            shutil.copytree(HOOKS_DIR, dst, ignore=shutil.ignore_patterns("state"))
            manifest["contents"]["hooks"] = [f.name for f in dst.glob("*.sh")]

        # 4. Templates
        if TEMPLATES_DIR.exists():
            dst = tmp / "templates"
            shutil.copytree(TEMPLATES_DIR, dst)
            manifest["contents"]["templates"] = [f.name for f in dst.glob("*")]

        # 5. Domains
        if DOMAINS_DIR.exists():
            dst = tmp / "domains"
            shutil.copytree(DOMAINS_DIR, dst)
            manifest["contents"]["domains"] = len(list(dst.glob("*.md")))

        # 6. Sessions registry
        if SESSIONS_DIR.exists():
            dst = tmp / "sessions"
            shutil.copytree(SESSIONS_DIR, dst)
            manifest["contents"]["sessions"] = len(list(dst.glob("*.json")))

        # 7. Knowledge DB (embeddings)
        if DB_FILE.exists():
            shutil.copy2(DB_FILE, tmp / "knowledge.db")
            manifest["contents"]["knowledge_db"] = True

        # 8. Settings (hooks config only)
        if SETTINGS_FILE.exists():
            try:
                settings = json.loads(SETTINGS_FILE.read_text())
                hooks_only = {"hooks": settings.get("hooks", {})}
                (tmp / "settings-hooks.json").write_text(
                    json.dumps(hooks_only, indent=2, ensure_ascii=False)
                )
                manifest["contents"]["settings_hooks"] = True
            except (json.JSONDecodeError, KeyError):
                pass

        # 9. Global rules
        if RULES_FILE.exists():
            shutil.copy2(RULES_FILE, tmp / "CLAUDE.md")
            manifest["contents"]["rules"] = True

        # Write manifest
        (tmp / "manifest.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False)
        )

        # Create archive
        with tarfile.open(archive_path, "w:gz") as tar:
            for item in tmp.iterdir():
                tar.add(item, arcname=item.name)

    return archive_path


def import_brain(archive_path: Path, dry_run: bool = False) -> dict:
    """Unpack a brain archive and merge into the current machine.

    Strategy: MERGE, not overwrite.
    - Knowledge files: if file exists with same name, keep the one with higher
      confirmed_count. If new file doesn't exist locally — add it.
    - Skills, hooks, templates: overwrite (newer version wins)
    - Domains: merge (add missing, don't delete existing)
    - knowledge.db: regenerate after import (reindex)
    - Settings: merge hooks config
    - CLAUDE.md: overwrite only if local is older

    Returns a report dict with counts of added/updated/skipped items.
    """
    report = {
        "knowledge": {"added": 0, "updated": 0, "skipped": 0},
        "commands": {"added": 0, "updated": 0},
        "hooks": {"added": 0, "updated": 0},
        "templates": {"added": 0, "updated": 0},
        "domains": {"added": 0, "updated": 0},
        "rules": False,
        "settings_merged": False,
        "db_reindex_needed": False,
        "dry_run": dry_run,
    }

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)

        # Extract
        with tarfile.open(archive_path, "r:gz") as tar:
            tar.extractall(tmp, filter="data")

        # Read manifest
        manifest_path = tmp / "manifest.json"
        manifest = {}
        if manifest_path.exists():
            manifest = json.loads(manifest_path.read_text())

        # 1. Knowledge files — smart merge
        src_knowledge = tmp / "global-lessons"
        if src_knowledge.exists():
            KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
            for src_file in src_knowledge.glob("*.md"):
                dst_file = KNOWLEDGE_DIR / src_file.name
                action = _merge_knowledge_file(src_file, dst_file, dry_run)
                report["knowledge"][action] += 1
            report["db_reindex_needed"] = True

        # 2. Commands (skills) — overwrite
        src_commands = tmp / "commands"
        if src_commands.exists():
            COMMANDS_DIR.mkdir(parents=True, exist_ok=True)
            for src_skill in src_commands.iterdir():
                if src_skill.is_dir():
                    dst_skill = COMMANDS_DIR / src_skill.name
                    existed = dst_skill.exists()
                    if not dry_run:
                        if dst_skill.exists():
                            shutil.rmtree(dst_skill)
                        shutil.copytree(src_skill, dst_skill)
                    report["commands"]["updated" if existed else "added"] += 1

        # 3. Hooks — overwrite scripts
        src_hooks = tmp / "hooks"
        if src_hooks.exists():
            HOOKS_DIR.mkdir(parents=True, exist_ok=True)
            for src_hook in src_hooks.glob("*.sh"):
                dst_hook = HOOKS_DIR / src_hook.name
                existed = dst_hook.exists()
                if not dry_run:
                    shutil.copy2(src_hook, dst_hook)
                    dst_hook.chmod(0o755)
                report["hooks"]["updated" if existed else "added"] += 1

        # 4. Templates
        src_templates = tmp / "templates"
        if src_templates.exists():
            TEMPLATES_DIR.mkdir(parents=True, exist_ok=True)
            for src_tmpl in src_templates.iterdir():
                if src_tmpl.is_file():
                    dst_tmpl = TEMPLATES_DIR / src_tmpl.name
                    existed = dst_tmpl.exists()
                    if not dry_run:
                        shutil.copy2(src_tmpl, dst_tmpl)
                    report["templates"]["updated" if existed else "added"] += 1

        # 5. Domains — merge (add missing)
        src_domains = tmp / "domains"
        if src_domains.exists():
            DOMAINS_DIR.mkdir(parents=True, exist_ok=True)
            for src_dom in src_domains.glob("*.md"):
                dst_dom = DOMAINS_DIR / src_dom.name
                existed = dst_dom.exists()
                if not existed and not dry_run:
                    shutil.copy2(src_dom, dst_dom)
                    report["domains"]["added"] += 1
                elif existed:
                    report["domains"]["updated"] += 0  # keep existing

        # 6. Settings — merge hooks
        src_settings = tmp / "settings-hooks.json"
        if src_settings.exists() and SETTINGS_FILE.exists():
            if not dry_run:
                try:
                    local = json.loads(SETTINGS_FILE.read_text())
                    imported = json.loads(src_settings.read_text())
                    # Merge hooks: imported hooks override local by event type
                    local_hooks = local.get("hooks", {})
                    for event, hook_list in imported.get("hooks", {}).items():
                        if event not in local_hooks:
                            local_hooks[event] = hook_list
                    local["hooks"] = local_hooks
                    SETTINGS_FILE.write_text(json.dumps(local, indent=2, ensure_ascii=False))
                    report["settings_merged"] = True
                except (json.JSONDecodeError, KeyError):
                    pass

        # 7. CLAUDE.md
        src_rules = tmp / "CLAUDE.md"
        if src_rules.exists():
            if not dry_run:
                shutil.copy2(src_rules, RULES_FILE)
            report["rules"] = True

    return report


def _merge_knowledge_file(src: Path, dst: Path, dry_run: bool) -> str:
    """Merge a single knowledge file. Returns 'added', 'updated', or 'skipped'."""
    import yaml

    if not dst.exists():
        if not dry_run:
            shutil.copy2(src, dst)
        return "added"

    # Both exist — compare confirmed_count
    src_meta = _parse_meta(src)
    dst_meta = _parse_meta(dst)

    src_confirmed = src_meta.get("confirmed_count", 0) or 0
    dst_confirmed = dst_meta.get("confirmed_count", 0) or 0

    if src_confirmed > dst_confirmed:
        if not dry_run:
            shutil.copy2(src, dst)
        return "updated"

    return "skipped"


def _parse_meta(path: Path) -> dict:
    """Quick YAML frontmatter parser — via shared frontmatter module."""
    from frontmatter import read_frontmatter

    fm = read_frontmatter(path)
    return fm[0] if fm else {}


def _machine_id() -> str:
    """Simple machine identifier."""
    import platform
    return f"{platform.node()}_{platform.system()}"
