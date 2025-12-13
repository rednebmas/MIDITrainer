# plans/000_overview.md

## Milestones (execute in order)

- **001: App skeleton + MIDI I/O foundation**
  - SwiftUI shell, MIDI input parsing, MIDI output endpoint selection, basic connect UX.

- **002: Sequence generation + MIDI playback**
  - 1-bar melody generator constrained to settings, rhythm library, MIDI out playback at BPM (default 80).

- **003: Practice engine + scoring + persistence**
  - Wait-for-correct input matching, record mistakes (scale degree + interval + note index), store sessions/sequences/attempts in SQLite.

- **004: Stats queries + graphs**
  - Aggregations: by scale degree, interval, note index, and confusion breakdowns; per-key and aggregated; graphs in UI.

- **005: Settings UI**
  - Edit and persist: key, scale, excluded degrees, allowed octaves, melody length, BPM; session snapshots.

- **006: Feedback polish**
  - Optional feedback (MIDI out root note/chord and/or simple local sound). Minor UX polish.

## Global constraints (must remain true)

- iPad-only, SwiftUI-only UI.
- No network.
- No rhythmic grading.
- Melodies only; 1 bar in 4/4; durations sum to 4 beats.
- Octave-sensitive correctness (MIDI note number match).
- Record expected vs guessed for:
  - scale degree
  - interval (relative to previous correct note; index 0 has “none”)
  - note index in melody

## Plans rules

- Plans contain **requirements + architecture details + acceptance criteria**, no code.
- Plans may name files/modules, schemas, tables, indexes, and data contracts.
- If you change any behavior, update the plan first.
