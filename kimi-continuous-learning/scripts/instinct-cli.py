#!/usr/bin/env python3
"""
Kimi Continuous Learning — Instinct Management CLI

Commands:
    status              List all instincts (grouped by scope)
    show <id>           Show single instinct detail
    evolve              Cluster instincts into skills
    promote [id]        Promote project instinct to global
    export              Export instincts
    import <file>       Import instincts
    purge --days N      Purge old observations
    decay               Apply confidence decay
    delete <id>         Delete an instinct
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import textwrap
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


LEARNING_DIR = Path.home() / ".kimi" / "learning"
GLOBAL_INSTINCTS_DIR = LEARNING_DIR / "instincts" / "personal"
GLOBAL_EVOLVED_DIR = LEARNING_DIR / "instincts" / "evolved" / "skills"
PROJECTS_DIR = LEARNING_DIR / "projects"
PROJECTS_REGISTRY = LEARNING_DIR / "projects.json"
KIMI_SKILLS_DIR = Path.home() / ".kimi" / "skills" / "learned"


def load_config() -> dict[str, Any]:
    config_path = LEARNING_DIR / "config.toml"
    defaults = {
        "learning": {
            "instinct": {
                "default_confidence": 0.5,
                "confidence_decay_days": 30,
                "auto_promote_threshold": 0.8,
                "auto_promote_min_projects": 2,
            },
            "evolution": {
                "min_confidence_for_skill": 0.7,
                "output_dir": str(KIMI_SKILLS_DIR),
                "sync_to_learned": True,
            },
            "observation": {
                "archive_after_days": 30,
            },
        }
    }
    # Minimal TOML parsing (only top-level tables we care about)
    if config_path.exists():
        try:
            import tomllib
            with open(config_path, "rb") as f:
                data = tomllib.load(f)
            defaults.update(data)
        except ImportError:
            try:
                import tomli as tomllib  # type: ignore
                with open(config_path, "rb") as f:
                    data = tomllib.load(f)
                defaults.update(data)
            except ImportError:
                pass
        except Exception:
            pass
    return defaults


def ensure_dirs() -> None:
    GLOBAL_INSTINCTS_DIR.mkdir(parents=True, exist_ok=True)
    GLOBAL_EVOLVED_DIR.mkdir(parents=True, exist_ok=True)
    KIMI_SKILLS_DIR.mkdir(parents=True, exist_ok=True)
    PROJECTS_DIR.mkdir(parents=True, exist_ok=True)


def list_instinct_files(scope: str | None = None, project_id: str | None = None) -> list[Path]:
    files: list[Path] = []
    if scope in (None, "global"):
        files.extend(GLOBAL_INSTINCTS_DIR.glob("*.yaml"))
        files.extend(GLOBAL_INSTINCTS_DIR.glob("*.yml"))
    if scope in (None, "project") and project_id:
        proj_dir = PROJECTS_DIR / project_id / "instincts" / "personal"
        if proj_dir.exists():
            files.extend(proj_dir.glob("*.yaml"))
            files.extend(proj_dir.glob("*.yml"))
    elif scope in (None, "project"):
        for proj_dir in PROJECTS_DIR.iterdir():
            if proj_dir.is_dir():
                personal = proj_dir / "instincts" / "personal"
                if personal.exists():
                    files.extend(personal.glob("*.yaml"))
                    files.extend(personal.glob("*.yml"))
    return files


def parse_instinct(path: Path) -> dict[str, Any] | None:
    text = path.read_text(encoding="utf-8")
    # Extract YAML frontmatter
    if not text.startswith("---"):
        return None
    parts = text.split("---", 2)
    if len(parts) < 3:
        return None
    try:
        import yaml
        frontmatter = yaml.safe_load(parts[1])
    except ImportError:
        # Fallback: regex parse key fields
        frontmatter = {}
        for line in parts[1].splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                frontmatter[k.strip()] = v.strip().strip('"').strip("'")

    body = parts[2].strip()
    frontmatter["_path"] = str(path)
    frontmatter["_body"] = body
    return frontmatter


def print_instinct(instinct: dict[str, Any]) -> None:
    print(f"  {instinct.get('id', 'unknown')}  (confidence: {instinct.get('confidence', 'N/A')}, scope: {instinct.get('scope', 'N/A')})")
    print(f"    Trigger: {instinct.get('trigger', 'N/A')}")
    print(f"    Domain:  {instinct.get('domain', 'N/A')}")
    print(f"    Path:    {instinct.get('_path', 'N/A')}")


def cmd_status(args: argparse.Namespace) -> int:
    ensure_dirs()
    files = list_instinct_files()
    if not files:
        print("No instincts found.")
        return 0

    global_files = [f for f in files if "projects/" not in str(f)]
    project_files = [f for f in files if "projects/" in str(f)]

    if args.global_only or not args.project_only:
        print("=== Global Instincts ===")
        for f in global_files:
            inst = parse_instinct(f)
            if inst:
                print_instinct(inst)
        if not global_files:
            print("  (none)")
        print()

    if args.project_only or not args.global_only:
        print("=== Project Instincts ===")
        by_project: dict[str, list[Path]] = {}
        for f in project_files:
            # Extract project hash from path: .../projects/<hash>/instincts/...
            match = re.search(r"projects/([^/]+)/instincts", str(f))
            if match:
                by_project.setdefault(match.group(1), []).append(f)
        if not by_project:
            print("  (none)")
        for pid, pfiles in sorted(by_project.items()):
            print(f"  Project: {pid}")
            for f in pfiles:
                inst = parse_instinct(f)
                if inst:
                    print_instinct(inst)
        print()

    print(f"Total: {len(files)} instincts")
    return 0


def cmd_show(args: argparse.Namespace) -> int:
    ensure_dirs()
    files = list_instinct_files()
    for f in files:
        inst = parse_instinct(f)
        if inst and inst.get("id") == args.id:
            print(f"---")
            for k, v in sorted(inst.items()):
                if k.startswith("_"):
                    continue
                print(f"{k}: {v}")
            print(f"---")
            print(inst.get("_body", ""))
            return 0
    print(f"Instinct '{args.id}' not found.", file=sys.stderr)
    return 1


def cmd_evolve(args: argparse.Namespace) -> int:
    ensure_dirs()
    cfg = load_config()
    min_conf = cfg.get("learning", {}).get("evolution", {}).get("min_confidence_for_skill", 0.7)

    files = list_instinct_files()
    instincts: list[dict[str, Any]] = []
    for f in files:
        inst = parse_instinct(f)
        if inst and float(inst.get("confidence", 0)) >= min_conf:
            instincts.append(inst)

    if not instincts:
        print("No instincts meet the minimum confidence threshold.")
        return 0

    print(f"Evolving {len(instincts)} instincts into skills...")

    if args.dry_run:
        print("[DRY RUN] Would create the following skills:")

    evolved: list[str] = []
    for inst in instincts:
        skill_id = inst.get("id", "unknown")
        skill_dir = GLOBAL_EVOLVED_DIR / skill_id
        if args.dry_run:
            print(f"  - {skill_id} → {skill_dir}/SKILL.md")
            evolved.append(skill_id)
            continue

        skill_dir.mkdir(parents=True, exist_ok=True)
        skill_md = skill_dir / "SKILL.md"

        description = inst.get("trigger", f"Learned pattern: {skill_id}")
        body = textwrap.dedent(f"""\
            ---
            name: {skill_id}
            description: {description}
            ---

            # {skill_id.replace("-", " ").title()}

            ## When to Use
            {inst.get("trigger", "When relevant.")}

            ## Pattern
            {inst.get("_body", "No detailed pattern available.")}

            ## Evidence
            Extracted from {inst.get("observation_count", 0)} observations.
            Confidence: {inst.get("confidence", "N/A")}.
            Source: {inst.get("source", "session-observation")}.
            """)
        skill_md.write_text(body, encoding="utf-8")
        evolved.append(skill_id)

        # Sync to ~/.kimi/skills/learned/
        if cfg.get("learning", {}).get("evolution", {}).get("sync_to_learned", True):
            target_dir = KIMI_SKILLS_DIR / skill_id
            target_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(skill_md, target_dir / "SKILL.md")

    print(f"Evolved {len(evolved)} skills.")
    return 0


def cmd_promote(args: argparse.Namespace) -> int:
    ensure_dirs()
    cfg = load_config()
    threshold = cfg.get("learning", {}).get("instinct", {}).get("auto_promote_threshold", 0.8)
    min_projects = cfg.get("learning", {}).get("instinct", {}).get("auto_promote_min_projects", 2)

    if args.id:
        # Promote specific instinct
        files = list_instinct_files(scope="project")
        for f in files:
            inst = parse_instinct(f)
            if inst and inst.get("id") == args.id:
                if args.dry_run:
                    print(f"[DRY RUN] Would promote {args.id} to global.")
                    return 0
                # Copy to global
                target = GLOBAL_INSTINCTS_DIR / f.name
                shutil.copy2(f, target)
                # Update scope in file
                content = target.read_text(encoding="utf-8")
                content = re.sub(r"^scope:.*$", "scope: global", content, flags=re.MULTILINE)
                content = re.sub(r"^project_id:.*$", "project_id: null", content, flags=re.MULTILINE)
                content = re.sub(r"^project_name:.*$", "project_name: null", content, flags=re.MULTILINE)
                target.write_text(content, encoding="utf-8")
                print(f"Promoted '{args.id}' to global scope.")
                return 0
        print(f"Project instinct '{args.id}' not found.", file=sys.stderr)
        return 1

    if args.auto:
        # Auto-promote qualifying instincts
        files = list_instinct_files(scope="project")
        by_id: dict[str, list[tuple[dict[str, Any], Path]]] = {}
        for f in files:
            inst = parse_instinct(f)
            if inst:
                by_id.setdefault(inst.get("id", ""), []).append((inst, f))

        promoted = 0
        for iid, items in by_id.items():
            if len(items) < min_projects:
                continue
            avg_conf = sum(float(i.get("confidence", 0)) for i, _ in items) / len(items)
            if avg_conf < threshold:
                continue
            if args.dry_run:
                print(f"[DRY RUN] Would auto-promote {iid} (avg confidence: {avg_conf:.2f}, projects: {len(items)})")
                continue
            # Promote the highest-confidence instance
            best_inst, best_path = max(items, key=lambda x: float(x[0].get("confidence", 0)))
            target = GLOBAL_INSTINCTS_DIR / best_path.name
            shutil.copy2(best_path, target)
            content = target.read_text(encoding="utf-8")
            content = re.sub(r"^scope:.*$", "scope: global", content, flags=re.MULTILINE)
            content = re.sub(r"^project_id:.*$", "project_id: null", content, flags=re.MULTILINE)
            content = re.sub(r"^project_name:.*$", "project_name: null", content, flags=re.MULTILINE)
            target.write_text(content, encoding="utf-8")
            print(f"Auto-promoted '{iid}' (confidence: {avg_conf:.2f}, projects: {len(items)})")
            promoted += 1

        print(f"Promoted {promoted} instincts to global scope.")
        return 0

    print("Usage: promote <id> | promote --auto [--dry-run]")
    return 1


def cmd_export(args: argparse.Namespace) -> int:
    ensure_dirs()
    files = list_instinct_files(
        scope=args.scope,
        project_id=args.project_id,
    )
    instincts: list[dict[str, Any]] = []
    for f in files:
        inst = parse_instinct(f)
        if inst:
            if args.domain and inst.get("domain") != args.domain:
                continue
            instincts.append(inst)

    output = args.output or "-"
    data = {
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "count": len(instincts),
        "instincts": instincts,
    }

    try:
        import yaml
        text = yaml.dump(data, allow_unicode=True, sort_keys=False)
    except ImportError:
        text = json.dumps(data, indent=2, ensure_ascii=False)

    if output == "-":
        print(text)
    else:
        Path(output).write_text(text, encoding="utf-8")
        print(f"Exported {len(instincts)} instincts to {output}")
    return 0


def cmd_import_file(args: argparse.Namespace) -> int:
    ensure_dirs()
    path = Path(args.file)
    if not path.exists():
        print(f"File not found: {path}", file=sys.stderr)
        return 1

    text = path.read_text(encoding="utf-8")
    try:
        import yaml
        data = yaml.safe_load(text)
    except ImportError:
        data = json.loads(text)

    instincts = data.get("instincts", data if isinstance(data, list) else [])
    imported = 0
    for inst in instincts:
        if not isinstance(inst, dict):
            continue
        iid = inst.get("id", "unknown")
        # Determine target dir based on scope
        scope = inst.get("scope", "global")
        if scope == "project" and inst.get("project_id"):
            target_dir = PROJECTS_DIR / inst["project_id"] / "instincts" / "personal"
        else:
            target_dir = GLOBAL_INSTINCTS_DIR
            inst["scope"] = "global"
            inst["project_id"] = None
            inst["project_name"] = None

        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / f"{iid}.yaml"

        try:
            import yaml
            frontmatter = yaml.dump(inst, allow_unicode=True, sort_keys=False)
        except ImportError:
            frontmatter = "\n".join(f"{k}: {v}" for k, v in inst.items())

        body = inst.get("_body", "")
        content = f"---\n{frontmatter}---\n\n{body}\n"
        target.write_text(content, encoding="utf-8")
        imported += 1

    print(f"Imported {imported} instincts.")
    return 0


def cmd_purge(args: argparse.Namespace) -> int:
    days = args.days or 30
    removed = 0
    for proj_dir in PROJECTS_DIR.iterdir():
        if not proj_dir.is_dir():
            continue
        obs = proj_dir / "observations.jsonl"
        if obs.exists():
            # For jsonl, we can't easily purge lines. Instead rotate the file.
            # For MVP: just archive old observations files
            archive_dir = proj_dir / "observations.archive"
            archive_dir.mkdir(parents=True, exist_ok=True)
            for f in archive_dir.glob("observations-*.jsonl"):
                mtime = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc)
                age = (datetime.now(timezone.utc) - mtime).days
                if age > days:
                    f.unlink()
                    removed += 1
    print(f"Purged {removed} archived observation files older than {days} days.")
    return 0


def cmd_decay(args: argparse.Namespace) -> int:
    ensure_dirs()
    cfg = load_config()
    decay_days = cfg.get("learning", {}).get("instinct", {}).get("confidence_decay_days", 30)

    files = list_instinct_files()
    decayed = 0
    now = datetime.now(timezone.utc)
    for f in files:
        inst = parse_instinct(f)
        if not inst:
            continue
        updated_str = inst.get("updated_at", inst.get("created_at", ""))
        if not updated_str:
            continue
        try:
            updated = datetime.fromisoformat(updated_str.replace("Z", "+00:00"))
        except ValueError:
            continue
        age_days = (now - updated).days
        if age_days > decay_days:
            conf = float(inst.get("confidence", 0.5))
            new_conf = max(0.3, conf - 0.05)
            if new_conf < conf:
                content = f.read_text(encoding="utf-8")
                content = re.sub(
                    r"^confidence:.*$",
                    f"confidence: {new_conf:.2f}",
                    content,
                    flags=re.MULTILINE,
                )
                content = re.sub(
                    r"^updated_at:.*$",
                    f"updated_at: {now.isoformat()}",
                    content,
                    flags=re.MULTILINE,
                )
                f.write_text(content, encoding="utf-8")
                decayed += 1
                print(f"Decayed '{inst.get('id')}' confidence: {conf:.2f} → {new_conf:.2f}")

    print(f"Applied decay to {decayed} instincts.")
    return 0


def cmd_delete(args: argparse.Namespace) -> int:
    files = list_instinct_files()
    for f in files:
        inst = parse_instinct(f)
        if inst and inst.get("id") == args.id:
            f.unlink()
            print(f"Deleted instinct '{args.id}'.")
            # Also remove evolved skill if exists
            skill_dir = GLOBAL_EVOLVED_DIR / args.id
            if skill_dir.exists():
                shutil.rmtree(skill_dir)
                print(f"Removed evolved skill '{args.id}'.")
            target_skill = KIMI_SKILLS_DIR / args.id
            if target_skill.exists():
                shutil.rmtree(target_skill)
                print(f"Removed synced skill '{args.id}'.")
            return 0
    print(f"Instinct '{args.id}' not found.", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="instinct-cli",
        description="Kimi Continuous Learning — Instinct Management",
    )
    sub = parser.add_subparsers(dest="cmd")

    # status
    p_status = sub.add_parser("status", help="List instincts")
    p_status.add_argument("--project-only", action="store_true")
    p_status.add_argument("--global-only", action="store_true")

    # show
    p_show = sub.add_parser("show", help="Show instinct detail")
    p_show.add_argument("id")

    # evolve
    p_evolve = sub.add_parser("evolve", help="Cluster instincts into skills")
    p_evolve.add_argument("--dry-run", action="store_true")
    p_evolve.add_argument("--project", dest="project_id")

    # promote
    p_promote = sub.add_parser("promote", help="Promote project instinct to global")
    p_promote.add_argument("id", nargs="?")
    p_promote.add_argument("--auto", action="store_true")
    p_promote.add_argument("--dry-run", action="store_true")

    # export
    p_export = sub.add_parser("export", help="Export instincts")
    p_export.add_argument("--output", "-o")
    p_export.add_argument("--scope", choices=["global", "project"])
    p_export.add_argument("--domain")
    p_export.add_argument("--project-id")

    # import
    p_import = sub.add_parser("import", help="Import instincts")
    p_import.add_argument("file")

    # purge
    p_purge = sub.add_parser("purge", help="Purge old observations")
    p_purge.add_argument("--days", type=int)

    # decay
    sub.add_parser("decay", help="Apply confidence decay")

    # delete
    p_delete = sub.add_parser("delete", help="Delete an instinct")
    p_delete.add_argument("id")

    args = parser.parse_args()
    if not args.cmd:
        parser.print_help()
        return 1

    handlers: dict[str, Any] = {
        "status": cmd_status,
        "show": cmd_show,
        "evolve": cmd_evolve,
        "promote": cmd_promote,
        "export": cmd_export,
        "import": cmd_import_file,
        "purge": cmd_purge,
        "decay": cmd_decay,
        "delete": cmd_delete,
    }

    return handlers[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
