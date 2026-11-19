# RFC 0010: Ship Spec Harness as a Claude Code plugin

Status: proposal. No code changes. The five spikes below are not started.

## Problem

Install copies about 120 files into each target and registers an edit-guard hook by hand.
Upgrades then compare those copies with the harness, and a repository that changed a copied file
gets a CONFLICT. A plugin could carry the commands, agents, skills and hooks from one pinned
version, so a target keeps only its own rules and memory.

## Proposal

Package the harness as a plugin with a manifest, and keep the target-side files that hold
project facts (AGENTS.md, RULES.md, `.memory/`, `ai_rules/`). The plugin provides commands,
agents, skills and the edit-guard hook. It is installed with `/plugin install` from a marketplace
entry pinned to a release tag.

## Spikes (proposed; each produces a written result, not code in main)

- **S1 Manifest.** Can `.claude-plugin/plugin.json` list the existing commands and agents
  without renaming them? Result: a list of files that cannot be shipped unchanged.
- **S2 Install footprint.** What does `/plugin install` write into a target, if anything? Result:
  an explicit list, to be compared with the current 122 files.
- **S3 Hook.** Does the edit guard run when declared in the plugin's hooks file with
  `${CLAUDE_PLUGIN_ROOT}`? Does it still need a `settings.local.json` entry? Result: yes or no,
  with a planted-fault control (a changed hook must block).
- **S4 Versions.** How is the plugin version tied to the release tag, and how does an existing
  `spec-harness update` target move to the plugin? Result: a migration table.
- **S5 Removal.** After a plugin uninstall, what remains in the target, and does a target that
  already has a copied install keep working? Result: a clean-target check.

## Not decided here

- Whether the plugin replaces the npm route or sits beside it.
- Marketplace hosting (a public marketplace versus a private one).

## Security

A plugin hook runs with the user's permissions on every matching event. The v008 review found a
third-party plugin hook that runs at session start and after git commands. Each shipped hook
must name its matcher and its command in the manifest, and must be reviewed as a release file.
