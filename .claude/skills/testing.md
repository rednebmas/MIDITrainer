---
name: testing
description: Use when writing or reviewing unit tests for this project
---

# Unit Testing Principles for MIDITrainer

## Core Philosophy

**Unmaintained tests are worse than no tests.** Tests that aren't run regularly, aren't kept in sync with the codebase, and aren't updated when code changes provide negative value - they give false confidence and create friction when making changes.

## Test Prioritization

### Prefer Integration Tests Over Unit Tests

Tests that verify how multiple components work together in realistic scenarios are **far more valuable** than small tests of isolated functions.

**Good:** A test that exercises the practice engine state machine - starting playback, receiving MIDI input, transitioning states, auto-advancing on success, auto-replaying on error.

**Less valuable:** A test that verifies a single pure function converts a MIDI note number to a note name.

### Why Integration Tests Win

1. **They catch real bugs** - Most bugs occur at component boundaries, not inside isolated functions
2. **They're more resilient to refactoring** - When you rename internal methods or restructure code, integration tests don't break if behavior is preserved
3. **They test what users care about** - Users don't care if `midiNoteToName()` works; they care if the whole flow works
4. **They require less maintenance** - One integration test can replace many unit tests

## What to Test

### High Value
- Practice engine state machine (state transitions, auto-advance, auto-replay)
- Spaced repetition logic (clearance distances, queue management, re-ask timing)
- Scoring logic (degree/interval computation)
- Database migrations and complex queries

### Medium Value
- Sequence generation with seeds (determinism)
- Settings persistence and retrieval

### Low Value (often skip)
- Pure formatting functions
- Simple computed properties
- View layout code

## Maintenance Rules

1. **Run tests before committing** - If tests don't pass, either fix them or delete them
2. **Update tests when changing code** - If a test fails after a code change, decide immediately: fix or delete
3. **Delete flaky tests** - Tests that sometimes pass and sometimes fail are worse than no tests
4. **Delete tests for removed features** - Dead code includes dead tests

## Test Commands

Run all tests:
```bash
xcodebuild -project MIDITrainer.xcodeproj -scheme MIDITrainer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=18.5' test
```

Run a specific test class:
```bash
xcodebuild -project MIDITrainer.xcodeproj -scheme MIDITrainer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=18.5' test -only-testing:MIDITrainerTests/PracticeEngineTests
```

Run a specific test method:
```bash
xcodebuild -project MIDITrainer.xcodeproj -scheme MIDITrainer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=18.5' test -only-testing:MIDITrainerTests/PracticeEngineTests/testAutoAdvanceOnPerfectSequence
```

## Test Structure Example

```swift
func testAutoReplayOnError() {
    // Setup: Create engine with mock dependencies
    let engine = PracticeEngine(
        midiService: mockMIDI,
        sequenceGenerator: seededGenerator,
        playbackScheduler: mockPlayback,
        // ... other dependencies
    )

    // Act: Play a question and make an error
    engine.playQuestion(settings: settings, seed: 123)

    // Simulate completing playback
    mockPlayback.simulatePlaybackComplete()

    // User plays wrong note then correct note
    mockMIDI.simulateNoteOn(60)  // wrong
    mockMIDI.simulateNoteOn(64)  // correct - completes sequence

    // Assert: Engine should auto-replay after error
    XCTAssertEqual(engine.state, .active(isPlayingBack: true))
    XCTAssertTrue(engine.isReplaying)
}
```

## When to Write Tests

- **Do write tests** for core business logic that's complex and error-prone
- **Do write tests** when debugging a tricky bug (regression test)
- **Don't write tests** just to hit coverage numbers
- **Don't write tests** for trivial code that's obviously correct
