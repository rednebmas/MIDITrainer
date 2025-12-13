# plans/006_feedback_polish.md

## Goal

Add lightweight feedback (optional) and minor UX polish without expanding scope.

## Requirements

Feedback:
- Correct note feedback:
  - Animation
- Correct sequence feedback:
  - Animation
  - MIDI out: short root note or root triad/chord (configurable)
- Settings toggles:
  - feedback type (MIDI)

Practice UX polish:
- Clear start/stop session controls
- Expected note index indicator
- Replay question button
- Midi does not need to always be displayed, confirm with modal dialog if last connected to device is not available
- Don't show recent midi events and remove debug actions
- Minor styling improvements you see fit

## Suggested files (non-binding)

- `Services/Feedback/FeedbackService.swift`
- `Features/Settings/FeedbackSection.swift`
- `Features/Practice/PracticeView.swift` (small updates)
