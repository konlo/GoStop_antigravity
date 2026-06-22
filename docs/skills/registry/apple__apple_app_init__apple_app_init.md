<!--
Copied skill source for documentation.
Original path: /Users/najongseong/git_repository/skills-registry/apple/apple_app_init/SKILL.md
Source group: registry
Skill name: apple_app_init
Original relative directory: apple/apple_app_init
-->

---
name: apple_app_init
description: Prevent common Xcode setup mistakes and guarantee a runnable iOS app project before any feature or code generation begins.
---

# apple_app_init.skill

## Purpose
Prevent common Xcode setup mistakes and guarantee a runnable iOS app project before any feature or code generation begins.

## 1. Skill Scope

This skill MUST run before:
- any app code generation
- any game logic generation
- any UI / SwiftUI code generation

If this skill fails, all downstream skills must stop.

## 2. Supported App Types
**supported_platforms:**
  - iOS

**supported_targets:**
  - iPhone

**supported_templates:**
  - iOS App (SwiftUI)

## 3. Hard Guardrails (❌ 절대 금지)
**forbidden:**
  **project_types:**
    - Swift Package
    - Command Line Tool
    - macOS App
    - Playground
    - Framework

  **ui_frameworks:**
    - UIKit (mixed with SwiftUI)

  **targets:**
    - macOS
    - watchOS
    - tvOS

⚠️ **If any forbidden item is detected → STOP immediately**

## 4. Mandatory Project Configuration (✅ 필수)
**required_configuration:**
  - project_type: Xcode Project
  - template: iOS App
  - interface: SwiftUI
  - language: Swift
  - lifecycle: SwiftUI App
  - deployment_target: iOS

## 5. Xcode Creation Procedure (Exact Path)

60: The assistant MUST instruct the user to follow this exact sequence:
61: 
62: **Step 0: Project Name**
63: → Ask the user: "What should be the Project Name?"
64: 
65: **Step 1: Xcode Wizard**
66: → **File**
67: → **New**
68: → **Project**
69: → **iOS**
70: → **App**
71: → **Product Name:** (Input User's Answer)
72: → **Interface:** SwiftUI
73: → **Language:** Swift
74: → **Life Cycle:** SwiftUI App

❗ **Do NOT mention Package, Workspace, or Playground at this stage.**

## 6. Preflight Validation Checklist (Critical)

Before proceeding, the assistant MUST confirm ALL of the following:

**preflight_checks:**
  - app_target_exists
  - run_scheme_exists
  - simulator_selected
  - bundle_identifier_set
  - signing_team_set

### Required Confirmation Questions

The assistant MUST ask:
1. Do you see a blue app icon (App Target) in the Project Navigator?
2. Is an iPhone Simulator selected next to the Run button?
3. Does the Run button ▶️ exist and is clickable?
4. Is Signing → Team set (Personal Team is OK)?

❌ **If ANY answer is "No" → STOP and fix first.**

## 7. Execution Guarantee Rule

This skill is considered PASSED only if:

**execution_status:**
  - build: success
  - run_on_simulator: success

If the app does not launch to the default SwiftUI preview screen, the skill FAILED.

## 8. Output Contract (On Success)

Only after success, the skill may output:

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

## 9. Failure Handling Policy

If the skill fails:

**on_failure:**
  **action:**
    - explain_exact_issue
    - provide_minimal_fix_steps
    - do_not_generate_any_app_code

⚠️ **Never continue with feature generation on a broken project.**

## 10. Design Philosophy (Internal)

This skill exists to eliminate non-obvious Apple ecosystem traps.

- Execution > cleverness
- Deterministic setup > flexible setup
- “Runs on simulator” is the only real success metric

✅ **Summary (한 줄)**
If the app does not run, nothing else matters.
