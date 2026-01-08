#!/usr/bin/env python3
"""Generate static site for Mathlib proof_wanted declarations."""

import json
import os
import subprocess
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

from jinja2 import Environment, FileSystemLoader


def get_mathlib_commit() -> str:
    """Get the mathlib commit hash from .lake/packages/mathlib."""
    mathlib_git = Path(".lake/packages/mathlib/.git")

    # Check if it's a git directory or a file (worktree/submodule)
    if mathlib_git.is_file():
        # It's a gitdir pointer, read the actual git directory
        content = mathlib_git.read_text().strip()
        if content.startswith("gitdir:"):
            git_dir = Path(content.split(":", 1)[1].strip())
            head_file = git_dir / "HEAD"
        else:
            head_file = mathlib_git / "HEAD"
    else:
        head_file = mathlib_git / "HEAD"

    if head_file.exists():
        head_content = head_file.read_text().strip()
        if head_content.startswith("ref:"):
            # It's a symbolic reference, resolve it
            ref_path = head_content.split(":", 1)[1].strip()
            ref_file = head_file.parent / ref_path
            if ref_file.exists():
                return ref_file.read_text().strip()
        else:
            # It's a detached HEAD, return the commit hash directly
            return head_content

    # Fallback: try using git command
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=".lake/packages/mathlib",
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "main"  # Ultimate fallback


def module_to_path(module: str) -> str:
    """Convert module name to file path."""
    return module.replace(".", "/") + ".lean"


def load_proof_wanted(jsonl_path: str) -> list[dict]:
    """Load proof_wanted declarations from JSONL file."""
    items = []
    with open(jsonl_path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                items.append(json.loads(line))
    return items


def group_by_module(items: list[dict]) -> list[tuple[str, list[dict]]]:
    """Group items by module, sorted alphabetically."""
    groups = defaultdict(list)
    for item in items:
        groups[item["module"]].append(item)

    # Sort items within each group by name
    for module in groups:
        groups[module].sort(key=lambda x: x["name"])

    # Return sorted list of (module, items) tuples
    return sorted(groups.items(), key=lambda x: x[0])


def generate_github_url(item: dict, commit: str) -> str:
    """Generate GitHub URL for an item."""
    path = module_to_path(item["module"])
    start = item["startLine"]
    end = item["endLine"]
    return f"https://github.com/leanprover-community/mathlib4/blob/{commit}/{path}#L{start}-L{end}"


def main():
    """Generate the static site."""
    # Load data
    items = load_proof_wanted("proof_wanted.jsonl")
    commit = get_mathlib_commit()

    # Add GitHub URLs to items
    for item in items:
        item["github_url"] = generate_github_url(item, commit)

    # Group by module
    modules = group_by_module(items)

    # Set up Jinja2
    env = Environment(loader=FileSystemLoader("templates"), autoescape=True)
    template = env.get_template("index.html")

    # Render template
    html = template.render(
        modules=modules,
        total_count=len(items),
        commit=commit,
        generated_date=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
    )

    # Write output
    output_dir = Path("_site")
    output_dir.mkdir(exist_ok=True)
    (output_dir / "index.html").write_text(html)

    print(
        f"Generated _site/index.html with {len(items)} items from {len(modules)} modules"
    )
    print(f"Mathlib commit: {commit[:7]}")


if __name__ == "__main__":
    main()
