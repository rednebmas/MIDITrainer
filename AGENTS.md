# AGENTS.md

This repo is a SwiftUI iPad app: a MIDI-based piano trainer. The app plays a 1-bar (4/4) melody over MIDI (constrained to a chosen scale/key), then waits for the user to play it back (pitch only). It records detailed mistakes (expected vs guessed scale degree + interval + note index) so we can graph systematic inaccuracies.

Agents must execute the milestone plans under `plans/` in order.

## How to work in this repo

- **Start here:** read `plans/000_overview.md`, then execute `plans/001_*.md`, `plans/002_*.md`, … in order.
- **Plans are the source of truth** for requirements and architecture details. If scope changes, update the relevant plan(s) first.
- **Plans must not contain code.** They may include file names, schemas, and acceptance criteria.

## Non-negotiable engineering rules

- **DRY (critical):** Search the codebase for existing logic before adding new code. Refactor to share.
- **Keep logic out of Views:** SwiftUI Views render state + forward user intent. Business logic lives in testable models/services.
- **Small, composable units:**
  - Prefer many small types over a few large ones.
  - Keep most functions under ~25 lines.
- **Determinism:** Sequence generation must support a seed for reproducible tests.
- **Threading:** Never block the main thread. MIDI callbacks + persistence writes must be off-main.
- **Correctness rules (product truth):**
  - iPad-first; local storage only (no network).
  - MIDI out only for playback (no audio synthesis required).
  - Melody is 1 bar in 4/4; durations sum to exactly 4 beats.
  - **No rhythmic grading.** Only pitch/interval correctness.
  - **Octave-sensitive** correctness (MIDI note number must match).
  - Input matching: do not advance to the next note until the current expected note is played correctly; record every wrong attempt.

## Architecture principles (high level)

- **Layering:**
  - Domain types are pure and framework-free (scales, degrees, intervals, sequences, attempts).
  - Services implement orchestration (MIDI I/O, generation, playback scheduling, scoring, persistence).
  - Feature models own observable UI state and call services.
- **Persistence:**
  - Use SQLite with migrations and indexes to support complex stats queries.
  - All DB access goes through repositories (no SQL in Views).
- **Testing:**
  - Unit tests for domain math (scale-degree mapping, interval computation, bar-sum rhythm validation, scoring).
  - Deterministic generator tests (seeded).
  - Lightweight integration tests for migrations + key stats queries.

## Build & test command

- Preferred validation: `xcodebuild -scheme MIDITrainer -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' -sdk iphonesimulator build` (uses the installed iPad Pro 11-inch (M5) simulator runtime).

## Definition of “done” for a milestone

- Plan acceptance criteria are met.
- Core business logic has tests where appropriate.
- No obvious duplication; responsibilities are cleanly split.
