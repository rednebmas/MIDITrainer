# plans/001_app_skeleton_and_midi.md

## Goal

Create the SwiftUI iPad app shell and a reliable BLE MIDI input/output layer with endpoint selection and live connectivity status.

## Requirements

### App shell
- App launches into a simple shell (tabs or root navigation) that can reach:
  - Practice (placeholder ok)
  - Settings (placeholder ok)
  - Stats (placeholder ok)

### MIDI
- Discover/connect BLE MIDI sources (input).
- Discover/select MIDI destination endpoint (output).
- UI shows:
  - connected source names
  - selected output name
  - basic connection state
- Parse incoming MIDI into domain events:
  - `NoteOn(noteNumber, velocity)`
  - `NoteOff(noteNumber)`
- Treat NoteOn velocity 0 as NoteOff.

## Architecture

Introduce a `MIDIService` boundary (names flexible, responsibilities not):

- Lifecycle:
  - start/stop
- Discovery:
  - list available input sources
  - list available output destinations
- Selection:
  - select destination for output
- Output:
  - send note on/off
- Input:
  - deliver parsed note events to the practice engine (via callback, async stream, or publisher)

Port/adapt patterns from existing `MIDIManager.swift` in MemoryFlash (input management) to this repo.

## Suggested files (non-binding)

- `Services/MIDI/MIDIService.swift`
- `Services/MIDI/CoreMIDIAdapter.swift` (CoreMIDI specifics)
- `Domain/MIDI/MIDINoteEvent.swift`
- `Features/Practice/PracticeView.swift` (placeholder UI showing MIDI status + test buttons)
- `Features/Practice/PracticeModel.swift` (connectivity state)

## Acceptance criteria

- You can connect a digital piano via Bluetooth MIDI and see it listed as an input source.
- Pressing keys produces parsed events (log/UI debug ok).
- You can select an output destination and send a test note out successfully.
- No crashes on connect/disconnect.
