# plans/006_feedback_polish.md

## Goal

Add lightweight feedback (optional) and minor UX polish without expanding scope.

## Requirements

Feedback options:
- Correct note feedback:
  - MIDI out: short root note or root triad/chord (configurable)
  - Optional local sound (only if easy; keep dependencies minimal)
- Incorrect note feedback:
  - MIDI out cue (e.g., root note) or local sound
- Settings toggles:
  - feedback enabled
  - feedback type (MIDI vs local sound, if both exist)

Practice UX polish:
- Clear start/stop session controls
- Expected note index indicator
- Replay question button

## Suggested files (non-binding)

- `Services/Feedback/FeedbackService.swift`
- `Features/Settings/FeedbackSection.swift`
- `Features/Practice/PracticeView.swift` (small updates)

## Acceptance criteria

- Feedback can be enabled/disabled.
- Feedback does not interfere with note matching (wrong notes still recorded; correct note still advances).
- No new large dependencies unless clearly justified.
