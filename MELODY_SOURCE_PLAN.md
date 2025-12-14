# Real Melody Source Implementation Plan

## Problem

The current random melody generator produces notes that are "in-key" but lack musical coherence - no stepwise motion, arpeggios, or melodic contour. Real melodies from actual songs would be much more useful for ear training.

## Research Summary

### Current System

`SequenceGenerator` creates melodies by:
1. Picking random scale degrees from allowed set
2. Picking random octaves from allowed set
3. Applying rhythm patterns from a library
4. Using seeds for reproducibility

This produces technically correct but unmusical sequences.

### Best MIDI Datasets

| Dataset | Size | License | Best For | Melodies Separated? |
|---------|------|---------|----------|---------------------|
| [POP909](https://github.com/music-x-lab/POP909-Dataset) | 909 songs | MIT | Pop melodies | **Yes** - MELODY track |
| [Lakh MIDI](https://colinraffel.com/projects/lmd/) | 176,581 files | CC-BY 4.0 | Variety | No - needs extraction |
| [kunstderfuge.com](https://www.kunstderfuge.com/) | 19,300 files | Public Domain | Classical | No |
| [PDMX](https://arxiv.org/html/2409.10831v1) | 250K+ files | Public Domain | Classical/Folk | No |

### Recommendation: POP909

POP909 is ideal because:
- MIT licensed (commercial use OK)
- Melodies already extracted into separate MELODY track
- Pop music (recognizable, singable phrases)
- Includes key/chord annotations for accurate transposition
- Manageable size (909 songs)

## Proposed Architecture

```
MelodySource (protocol)
├── RandomMelodySource (current behavior)
├── RealMelodySource (from MIDI library)
│   ├── filters by length range
│   ├── transposes to current key
│   └── adjusts to allowed octaves
└── (future: HybridMelodySource - real phrases with random variations)
```

## Implementation Phases

### Phase 1: Core Infrastructure

1. Add `MelodySource` protocol to abstract melody generation
2. Refactor `SequenceGenerator` to use a `MelodySource`
3. Add setting for melody source selection (Random / Real Melodies)
4. Change melody length from fixed value to **range** (e.g., 3-6 notes)

### Phase 2: MIDI Library Processing

1. Clone POP909 dataset
2. Extract melody phrases from MELODY tracks
3. Convert to compact interval-based format
4. Bundle as JSON in app (~1-2 MB for all phrases)
5. Index by phrase length for fast lookup

### Phase 3: Real Melody Source Implementation

1. Implement `RealMelodySource` that picks random phrases matching length range
2. Transpose phrase intervals to current key/scale
3. Shift octaves to match allowed octave range
4. Use seed for deterministic phrase selection

### Phase 4: Settings UI

1. Add "Melody Source" picker: Random / Real Melodies
2. Change "Notes per sequence" to a range slider (min-max)
3. Optionally: genre filter (if we add more datasets later)

## Data Format

Pre-process MIDI into compact phrase format (no runtime MIDI parsing):

```swift
struct MelodyPhrase: Codable {
    let intervals: [Int]      // Semitones from first note: [0, 2, 4, 2, 0]
    let durations: [Double]   // Beat durations: [1.0, 0.5, 0.5, 1.0, 1.0]
    let sourceId: String      // For attribution: "pop909_001"
}
```

Benefits:
- Transposition to any key (add root MIDI note to intervals)
- Octave shifting (add/subtract 12 from all intervals)
- Tiny file size (~50-100 bytes per phrase)
- No MIDI parsing at runtime
- Seed-based reproducibility maintained

## Transposition Logic

```swift
func transpose(phrase: MelodyPhrase, toKey key: Key, octave: Int) -> [UInt8] {
    let rootMidi = UInt8((octave + 1) * 12 + key.root.rawValue)
    return phrase.intervals.map { interval in
        UInt8(clamping: Int(rootMidi) + interval)
    }
}
```

## Open Questions

1. **Dataset scope**: Start with POP909 only, or include classical from kunstderfuge?
2. **Attribution**: Show source song name in UI, or keep invisible?
3. **Phrase extraction**: All lengths, or focus on 3-8 note phrases?
4. **Hybrid mode**: Option to take real phrase and randomize one note?

## File Changes Required

### New Files
- `MelodySource.swift` - Protocol definition
- `RandomMelodySource.swift` - Current behavior extracted
- `RealMelodySource.swift` - New phrase-based source
- `MelodyPhrase.swift` - Data model for phrases
- `MelodyLibrary.swift` - Loads and indexes bundled phrases
- `phrases.json` - Bundled phrase data (in Resources)

### Modified Files
- `SequenceGenerator.swift` - Use MelodySource protocol
- `PracticeSettingsSnapshot.swift` - Add melodySource, lengthRange
- `SettingsView.swift` - Add source picker, range slider
- `SettingsStore.swift` - Persist new settings

## External Tools Needed

Python script to process POP909 MIDI files:
1. Parse MIDI melody tracks
2. Extract note sequences
3. Convert to interval format
4. Quantize rhythms
5. Output as JSON

## References

- [POP909 Dataset](https://github.com/music-x-lab/POP909-Dataset)
- [Lakh MIDI Dataset](https://colinraffel.com/projects/lmd/)
- [kunstderfuge.com](https://www.kunstderfuge.com/)
- [Awesome MIDI Sources](https://github.com/albertmeronyo/awesome-midi-sources)
- [PDMX Dataset](https://arxiv.org/html/2409.10831v1)
