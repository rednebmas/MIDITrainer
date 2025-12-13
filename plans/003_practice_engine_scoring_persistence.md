# plans/003_practice_engine_scoring_persistence.md

## Goal

Implement the practice loop: play a question, wait-for-correct note-by-note input (pitch only), record every wrong attempt with rich metadata, and persist everything to SQLite for later stats queries.

## Requirements

### Practice loop behavior
- After playback, engine enters “awaiting input”.
- For expected note index `i`:
  - On incoming NoteOn:
    - If MIDI note number != expected: record a mistake attempt; do not advance.
    - If MIDI note number == expected: record a correct attempt; advance to i+1.
- Engine completes when the final note is played correctly.
- Session ends when user stops manually or changes settings.

### Scoring metadata to persist (per mistake)
Store enough to graph and query later:
- `expectedMidiNoteNumber`
- `guessedMidiNoteNumber`
- `expectedScaleDegree` (relative to current key/scale)
- `guessedScaleDegree`
- `expectedInterval` (previous correct → expected; for index 0 use “none”)
- `guessedInterval` (previous correct → guessed; for index 0 use “none”)
- `noteIndexInMelody` (0-based)
- `key`, `scale`
- `timestamp`
- `sessionId`, `sequenceId`

Also store correct attempts (at least: expected midi, timestamp, note index), so you can compute rates and derive “previous correct note” cleanly.

### Persistence requirements
- Local SQLite with:
  - explicit migrations
  - indexes to support stats queries
  - repositories wrapping all DB I/O
- The persisted model must support:
  - multiple sessions
  - multiple sequences per session
  - per-sequence notes (the expected melody)
  - per-note attempts (correct/mistake)

## SQLite schema (conceptual)

Tables (names flexible; relationships required):

- `settings_profile` (saved user settings presets, optional if you store a single “current settings” row)
- `settings_snapshot` (immutable settings used for a given session/sequence)
- `practice_session`
- `melody_sequence`
- `melody_note` (expected notes with index/start/duration/midi)
- `note_attempt` (user attempts; correct or mistake)

Recommended indexes:
- `note_attempt(key, scale)`
- `note_attempt(expectedScaleDegree)`
- `note_attempt(guessedScaleDegree)`
- `note_attempt(expectedInterval)`
- `note_attempt(guessedInterval)`
- `note_attempt(noteIndexInMelody)`
- `note_attempt(sequenceId)`
- `note_attempt(sessionId)`
- `note_attempt(timestamp)`

## Suggested files (non-binding)

- `Services/PracticeEngine/PracticeEngine.swift`
- `Services/Scoring/ScoringService.swift`
- `Persistence/SQLite/Database.swift` (open, migrations)
- `Persistence/Repositories/SessionRepository.swift`
- `Persistence/Repositories/SequenceRepository.swift`
- `Persistence/Repositories/AttemptRepository.swift`
- `Features/Practice/PracticeModel.swift`

## Acceptance criteria

- You can run: Play Question → user plays notes → app advances only when correct.
- Every wrong note is recorded with expected/guessed scale degree + interval + note index.
- Data persists across relaunch.
- Unit tests cover:
  - scale degree mapping (key+scale → degree for a MIDI note)
  - interval computation between MIDI notes
  - mistake descriptor generation for note index 0 vs >0
- Integration test: migrations create schema + basic insert/query works.
