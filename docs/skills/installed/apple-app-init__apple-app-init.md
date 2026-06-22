<!--
Copied skill source for documentation.
Original path: /Users/najongseong/.codex/skills/apple-app-init/SKILL.md
Source group: installed
Skill name: apple-app-init
Original relative directory: apple-app-init
-->

---
name: apple-app-init
description: "Initialize and validate a runnable Xcode iOS SwiftUI App project before any feature generation. Use when starting a new Apple app, bootstrapping an iPhone target, or recovering from setup issues. Enforce iOS App (SwiftUI), Swift language, SwiftUI App lifecycle, and stop immediately if forbidden project types, frameworks, or targets are detected."
---

# Apple App Init

Prevent Xcode setup mistakes and guarantee a runnable iOS app before any app, game, or UI code generation.

## Mandatory Scope Gate

Run this skill before:
- Any app code generation
- Any game logic generation
- Any UI or SwiftUI code generation

If this skill fails, stop all downstream skills.

## Supported Configuration

- Platform: iOS
- Target device class: iPhone
- Template: iOS App (SwiftUI)

## Hard Guardrails

Stop immediately if any forbidden setup is detected.

### Forbidden Project Types

- Swift Package
- Command Line Tool
- macOS App
- Playground
- Framework

### Forbidden UI/Target Mix

- UIKit mixed with SwiftUI
- macOS target
- watchOS target
- tvOS target

## Mandatory Project Configuration

Require all of the following:
- Project type: Xcode Project
- Template: iOS App
- Interface: SwiftUI
- Language: Swift
- Life Cycle: SwiftUI App
- Deployment target: iOS

## Exact Xcode Creation Path

Instruct this exact sequence:
- Xcode
- File
- New
- Project
- iOS
- App
- Interface: SwiftUI
- Language: Swift
- Life Cycle: SwiftUI App

Do not mention Package, Workspace, or Playground at this stage.

## Preflight Validation Checklist

Confirm all checks before any code work:
- `app_target_exists`
- `run_scheme_exists`
- `simulator_selected`
- `bundle_identifier_set`
- `signing_team_set`

Ask these required confirmation questions:
1. Do you see a blue app icon (App Target) in the Project Navigator?
2. Is an iPhone Simulator selected next to the Run button?
3. Does the Run button (`▶`) exist and is clickable?
4. Is Signing -> Team set (Personal Team is OK)?

If any answer is "No", stop and provide only minimal setup fixes.

## Execution Guarantee Rule

This skill passes only if both are true:
- Build succeeds
- App runs on simulator successfully

If the app does not launch to the default SwiftUI screen, mark this skill as failed.

## Success Output Contract

Only after pass, output:

```yaml
apple_app_init_result:
  status: READY
  platform: iOS
  ui: SwiftUI
  language: Swift
  next_allowed_skills:
    - app_ui_skill
    - game_engine_skill
    - gostop_rules_core
```

## Failure Policy

On failure:
- Explain the exact issue
- Provide minimal fix steps
- Do not generate any app code

Execution over cleverness. Deterministic setup over flexibility.
If the app does not run, nothing else matters.
