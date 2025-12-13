# plans/005_settings_ui.md

## Goal

Implement Settings UI and persistence: user can configure generation constraints and practice parameters; sessions use immutable snapshots.

## Requirements

Settings fields:
- Key (representation must map cleanly to MIDI pitch class)
- Scale type (at minimum: major, natural minor; extendable)
- Excluded degrees (multi-select)
- Allowed octave set (multi-select, e.g., 2–6)
- Melody length (number of notes)
- BPM (default 80)

Persistence:
- Save settings locally.
- When a session starts, create an immutable settings snapshot and attach it to session/sequence records so stats reflect the active context.

UX:
- Provide an “Apply” flow so Practice uses a coherent settings snapshot.

## Suggested files (non-binding)

- `Features/Settings/SettingsView.swift`
- `Features/Settings/SettingsModel.swift`
- `Domain/Settings/SettingsProfile.swift`
- `Persistence/Repositories/SettingsRepository.swift`

## Acceptance criteria

- Changing settings affects newly generated questions immediately after apply.
- Settings restore after relaunch.
- Practice sessions record which settings snapshot was active.
