# plans/002_sequence_generation_and_playback.md

## Goal

Generate 1-bar (4/4) melodies constrained to the selected scale/key and settings, and play them out over MIDI at a configurable BPM (default 80).

## Requirements

### Settings snapshot input (read-only for generation)
Generator consumes a settings snapshot containing:
- key
- scale type
- excluded scale degrees
- allowed octave set
- melody length (number of notes)
- BPM (default 80)

### Melody constraints
- Melody is **melodic single notes only**.
- Total rhythmic duration must sum to exactly **4 beats**.
- Pitch selection must always stay within the selected scale (after applying excluded degrees).

### Rhythm library
- Provide rhythm patterns that sum to 4 beats and are “pop/rock common”:
  - half, quarter, eighth, sixteenth groupings
  - triplet feel patterns
  - a few syncopations
- Rhythm is **not graded**, but is used for playback scheduling.
- Melody length is configurable; generator must reconcile length vs rhythm pattern selection:
  - Either choose patterns whose note count matches length, or
  - allow ties/rests/held notes to satisfy length requirements (choose one approach and document it).

### Determinism
- Sequence generation must support a seed (for tests and reproducibility).

### Playback
- Use BPM and the generated rhythm to schedule MIDI NoteOn/Off to the selected destination.
- Playback must not block UI.
- Practice screen provides “Play Question” and “Replay” controls.

## Domain data contract

A generated sequence must expose (at minimum):
- ordered notes with:
  - `midiNoteNumber`
  - `startBeat`
  - `durationBeats`
  - `index` (0-based)
- metadata:
  - key, scale, excluded degrees, allowed octaves
  - seed (optional, but recommended for reproducibility)

## Suggested files (non-binding)

- `Domain/Music/Key.swift`, `Scale.swift`, `ScaleDegree.swift`, `Interval.swift`
- `Domain/Practice/MelodyNote.swift`, `MelodySequence.swift`
- `Services/SequenceGenerator/RhythmLibrary.swift`
- `Services/SequenceGenerator/SequenceGenerator.swift`
- `Services/PracticeEngine/PlaybackScheduler.swift`

## Acceptance criteria

- Unit test: rhythm patterns validate to exactly 4 beats.
- Unit test: with a fixed seed + settings snapshot, generator yields a stable sequence.
- Pressing “Play Question” sends MIDI out matching the generated sequence timing.
- Generated notes always fall within the scale and allowed octave set, respecting excluded degrees.
