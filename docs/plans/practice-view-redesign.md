# Practice View Redesign: Game-Like UI

## Overview

Transform the current utilitarian List-based PracticeView into an engaging, game-like experience with animations, visual feedback, and clear progress tracking.

## Current State

The existing PracticeView uses a standard SwiftUI `List` with sections:
- Bordered buttons (Start/Next/Replay) in a row
- Small 14px progress dots
- Text-heavy stats (first-try accuracy, re-ask queue)
- Inline scheduler debug info
- MIDI device picker in same view

**Problem:** Feels like a settings screen, not a game.

---

## Proposed Layout

```
┌─────────────────────────────────────────────────┐
│                   TOP BAR                        │
│  ┌─────────┐   ┌─────────────────┐  ┌────────┐  │
│  │ 85%     │   │ ████████░░ 24/30│  │🔥 5    │  │
│  │accuracy │   │  daily goal     │  │streak  │  │
│  └─────────┘   └─────────────────┘  └────────┘  │
├─────────────────────────────────────────────────┤
│                                                  │
│                  CENTER STAGE                    │
│                                                  │
│           ⚪   ⚪   🟡   ⚪   ⚪                  │
│                    ↑                             │
│              (pulsing glow)                      │
│                                                  │
│              "First note: C"                     │
│                                                  │
│                                                  │
├─────────────────────────────────────────────────┤
│                  BOTTOM BAR                      │
│                                                  │
│    🎹 Roland FP-30X ● Connected                  │
│                                                  │
│              ┌─────────────┐                     │
│              │   ▶ START   │                     │
│              └─────────────┘                     │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

## Component Breakdown

### 1. Top Stats Bar (`GameStatsBarView`)

Three key metrics displayed horizontally:

| Element | Display | Notes |
|---------|---------|-------|
| **Accuracy** | Circular progress ring + percentage | Based on `firstTryAccuracy` from model |
| **Daily Goal** | Horizontal progress bar + "X/Y" | New feature: track questions answered today |
| **Streak** | Fire emoji + count | Consecutive perfect sequences |

**Daily Goal Feature:**
- Store daily goal in `SettingsStore` (default: 30 questions)
- Track questions answered today (reset at midnight)
- Progress bar fills as user approaches goal
- Celebratory animation when goal is reached

### 2. Center Stage (`NoteOrbsView`)

The main gameplay area featuring large, animated note orbs.

**Orb States:**
| State | Appearance |
|-------|------------|
| Pending | Muted gray, subtle float animation |
| Awaiting (current) | Bright glow, pulsing ring animation |
| Correct | Green fill, scale bounce, particle burst |
| Error | Red flash, shake animation |
| Completed | Filled green, connected by success line |

**Orb Specifications:**
- Size: 44-56pt diameter (vs current 14pt)
- Spacing: 16-24pt between orbs
- Animation: Spring-based for organic feel

**Additional Elements:**
- "First note: X" hint below orbs (when sequence loaded)
- Floating feedback text ("Perfect!", "Try again") on sequence completion

### 3. Bottom Action Bar (`ActionBarView`)

Simplified single-button design with MIDI status.

**MIDI Status Display:**
- Device name (e.g., "Roland FP-30X")
- Connection indicator: ● green (connected), ○ gray (offline), ⚠ orange (no device)
- Tap to open MIDI settings sheet

**Primary Action Button:**
- **No sequence:** "START" - begins first question
- **Sequence active:** "REPLAY" - replays current sequence
- Large, prominent button (full width or 60% width centered)
- Disabled state during playback with loading indicator

**Optional:** Small "Skip" button (text button, not prominent) - can be added later if needed

---

## Animations Specification

### Note Orb Animations

```swift
// Pulse animation for awaiting state
withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
    pulseScale = 1.15
    glowOpacity = 0.8
}

// Success animation
withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
    scale = 1.3  // bounce up
}
withAnimation(.spring(response: 0.3).delay(0.15)) {
    scale = 1.0  // settle back
    fillColor = .green
}

// Error animation
withAnimation(.default.repeatCount(3, autoreverses: true).speed(4)) {
    offset.x = 8  // shake
}
withAnimation(.easeOut(duration: 0.3)) {
    flashColor = .red  // flash
}
```

### Sequence Transitions

| Event | Animation |
|-------|-----------|
| New sequence starts | Orbs fade in with staggered spring (0.05s delay each) |
| Sequence completed (perfect) | All orbs pulse green, "Perfect!" scales in |
| Auto-advance | Crossfade to new orbs (0.3s) |
| Replay triggered | Orbs reset with quick fade (0.2s) |

### Stats Animations

- Accuracy ring: Animated stroke on value change
- Daily progress bar: Smooth width transition
- Streak counter: Scale bounce when incrementing, fire grows larger at milestones (5, 10, 25...)

---

## New Files to Create

| File | Purpose |
|------|---------|
| `Features/Practice/Views/GameStatsBarView.swift` | Top bar with accuracy, daily goal, streak |
| `Features/Practice/Views/NoteOrbView.swift` | Individual animated orb component |
| `Features/Practice/Views/NoteOrbsContainerView.swift` | Horizontal layout of orbs + hint text |
| `Features/Practice/Views/ActionBarView.swift` | Bottom bar with MIDI status + action button |
| `Features/Practice/Views/FloatingFeedbackView.swift` | "Perfect!" / "Try again" overlay |
| `Features/Practice/Animations/OrbAnimations.swift` | Reusable animation modifiers |
| `Features/Practice/Views/MIDISettingsSheet.swift` | Sheet for MIDI device selection |

## Files to Modify

| File | Changes |
|------|---------|
| `PracticeView.swift` | Complete rewrite - ZStack layout composing new views |
| `PracticeModel.swift` | Add streak tracking, daily count, goal progress |
| `SettingsStore.swift` | Add `dailyGoal: Int` setting |

---

## Data Model Additions

### PracticeModel additions:

```swift
@Published private(set) var currentStreak: Int = 0
@Published private(set) var questionsAnsweredToday: Int = 0
@Published private(set) var dailyGoal: Int = 30  // from SettingsStore
```

### Persistence:

- Store `questionsAnsweredToday` with date in UserDefaults or SQLite
- Reset count when date changes (check on app launch / question completion)
- Streak persists across sessions, resets on error

---

## Implementation Phases

### Phase A: Layout Restructure
1. Create new view files (empty shells)
2. Rewrite PracticeView with ZStack layout
3. Move MIDI picker to sheet
4. Basic styling (dark background, spacing)

**Acceptance criteria:**
- No more List-based UI
- MIDI settings accessible via sheet
- Layout matches proposed structure

### Phase B: Note Orbs
1. Implement NoteOrbView with state-driven colors
2. Add pulse animation for awaiting state
3. Add success/error animations
4. Create container with proper spacing

**Acceptance criteria:**
- Orbs are 44pt+ diameter
- Current note has visible pulse animation
- Correct notes animate green with bounce
- Wrong notes shake and flash red

### Phase C: Stats & Action Bar
1. Implement GameStatsBarView with accuracy ring
2. Add daily goal tracking + progress bar
3. Add streak counter with fire emoji
4. Implement ActionBarView with single button + MIDI status

**Acceptance criteria:**
- Accuracy shows as circular ring
- Daily progress visible
- Streak increments on perfect sequences
- Single action button handles Start/Replay states
- MIDI device name and status visible

### Phase D: Polish
1. Add floating feedback text ("Perfect!")
2. Staggered orb entrance animations
3. Sequence transition animations
4. Haptic feedback on success/error

**Acceptance criteria:**
- Feedback text appears on sequence completion
- Smooth transitions between sequences
- Haptic feedback fires appropriately

---

## Visual Design Notes

### Color Palette (suggestion)
- Background: Dark gradient (`#1a1a2e` → `#16213e`)
- Orb pending: `#4a4a6a` with subtle glow
- Orb awaiting: `#ffd700` (gold) with bright pulse
- Orb success: `#00d26a` (green)
- Orb error: `#ff4757` (red)
- Accent/buttons: `#4dabf7` (blue)

### Typography
- Stats numbers: SF Pro Rounded, bold
- Labels: SF Pro, medium, secondary color
- Feedback text: SF Pro Rounded, heavy, large

---

## Questions / Decisions Needed

1. **Daily goal settings UI:** Add to existing Settings tab, or allow editing from tapping the progress bar?
2. **Streak persistence:** Reset only on error, or also reset after X hours of inactivity?
3. **Skip button:** Include from start, or add later if users request it?
4. **Sound effects:** Out of scope for this plan, or include toggle for UI sounds?
