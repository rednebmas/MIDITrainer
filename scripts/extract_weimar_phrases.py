#!/usr/bin/env python3
"""
Extract melody phrases with chord data from the Weimar Jazz Database.
Outputs JSON in a format compatible with the app's melody library system.

To download the Weimar Jazz Database:
1. Visit https://jazzomat.hfm-weimar.de/dbformat/dboverview.html
2. Download wjazzd.db (SQLite database)
3. Place it in: Resources/WeimarJazzDB/wjazzd.db
"""

import sqlite3
import json
import os
import sys
from collections import defaultdict
from typing import NamedTuple

DB_PATH = "../Resources/WeimarJazzDB/wjazzd.db"
OUTPUT_PATH = "../MIDITrainer/Resources/weimar_jazz_phrases.json"

# Phrase length constraints
MIN_PHRASE_LENGTH = 3
MAX_PHRASE_LENGTH = 12


class MelodyNote(NamedTuple):
    eventid: int
    pitch: float
    duration: float
    onset: float
    bar: int
    beat: int


class ChordEvent(NamedTuple):
    onset: float
    bar: int
    beat: int
    chord: str
    bass_pitch: int


class PhraseData(NamedTuple):
    melid: int
    start_event: int
    end_event: int
    notes: list[MelodyNote]
    chords: list[ChordEvent]
    performer: str
    title: str
    key: str


def get_connection():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    db_path = os.path.join(script_dir, DB_PATH)

    if not os.path.exists(db_path):
        print("Error: Weimar Jazz Database not found!", file=sys.stderr)
        print(f"Expected location: {db_path}", file=sys.stderr)
        print("", file=sys.stderr)
        print("To download the database:", file=sys.stderr)
        print("1. Visit https://jazzomat.hfm-weimar.de/dbformat/dboverview.html", file=sys.stderr)
        print("2. Download wjazzd.db (SQLite database)", file=sys.stderr)
        print("3. Place it in: Resources/WeimarJazzDB/wjazzd.db", file=sys.stderr)
        sys.exit(1)

    return sqlite3.connect(db_path)


def get_solo_info(conn) -> dict:
    """Get metadata for all solos."""
    cursor = conn.execute("""
        SELECT s.melid, s.performer, c.title, s.key
        FROM solo_info s
        JOIN composition_info c ON s.compid = c.compid
    """)
    return {row[0]: {"performer": row[1], "title": row[2], "key": row[3]} for row in cursor}


def get_phrase_boundaries(conn, melid: int) -> list[tuple[int, int]]:
    """Get phrase start/end event indices for a solo."""
    cursor = conn.execute("""
        SELECT start, end FROM sections
        WHERE melid = ? AND type = 'PHRASE'
        ORDER BY start
    """, (melid,))
    return [(row[0], row[1]) for row in cursor]


def get_melody_notes(conn, melid: int) -> list[MelodyNote]:
    """Get all melody notes for a solo, ordered by onset."""
    cursor = conn.execute("""
        SELECT eventid, pitch, duration, onset, bar, beat
        FROM melody
        WHERE melid = ?
        ORDER BY onset
    """, (melid,))
    return [MelodyNote(*row) for row in cursor]


def get_chords(conn, melid: int) -> list[ChordEvent]:
    """Get all chord events for a solo, ordered by onset."""
    cursor = conn.execute("""
        SELECT onset, bar, beat, chord, bass_pitch
        FROM beats
        WHERE melid = ? AND chord IS NOT NULL AND length(chord) > 0
        ORDER BY onset
    """, (melid,))
    return [ChordEvent(*row) for row in cursor]


def get_chords_for_phrase(all_chords: list[ChordEvent],
                          phrase_notes: list[MelodyNote]) -> list[ChordEvent]:
    """Get chords that fall within the time range of a phrase."""
    if not phrase_notes:
        return []

    start_onset = phrase_notes[0].onset
    end_onset = phrase_notes[-1].onset + phrase_notes[-1].duration

    phrase_chords = []
    last_chord_before = None

    for chord in all_chords:
        if chord.onset < start_onset:
            last_chord_before = chord
        elif chord.onset <= end_onset:
            phrase_chords.append(chord)

    # Include the chord that was active at phrase start
    if last_chord_before and (not phrase_chords or phrase_chords[0].onset > start_onset):
        phrase_chords.insert(0, last_chord_before)

    return phrase_chords


def notes_to_intervals(notes: list[MelodyNote]) -> list[int]:
    """Convert MIDI pitches to intervals from first note."""
    if not notes:
        return []
    first_pitch = int(notes[0].pitch)
    return [int(note.pitch) - first_pitch for note in notes]


def notes_to_durations(notes: list[MelodyNote]) -> list[float]:
    """Extract durations, normalized to the beat."""
    return [round(note.duration, 4) for note in notes]


def chords_to_relative(chords: list[ChordEvent],
                       phrase_notes: list[MelodyNote],
                       phrase_key: str) -> list[dict]:
    """Convert chords to relative format with beat positions.

    Returns list of {beat_offset, chord} where beat_offset is beats from phrase start.
    """
    if not phrase_notes or not chords:
        return []

    phrase_start_onset = phrase_notes[0].onset

    relative_chords = []
    for chord in chords:
        # Calculate beat offset from phrase start
        # We'll use onset time difference (in seconds) for now
        beat_offset = round(chord.onset - phrase_start_onset, 4)
        relative_chords.append({
            "offset": beat_offset,
            "chord": chord.chord,
            "bass": chord.bass_pitch
        })

    return relative_chords


def extract_phrases(conn) -> list[dict]:
    """Extract all phrases from the database."""
    solo_info = get_solo_info(conn)
    phrases_by_length = defaultdict(list)

    total_phrases = 0
    skipped_chromatic = 0
    skipped_length = 0

    for melid, info in solo_info.items():
        phrase_boundaries = get_phrase_boundaries(conn, melid)
        all_notes = get_melody_notes(conn, melid)
        all_chords = get_chords(conn, melid)

        # Create a mapping from event index (0-based) to note
        # The sections table uses 0-based indices
        note_by_index = {}
        for i, note in enumerate(all_notes):
            note_by_index[i] = note

        for start_idx, end_idx in phrase_boundaries:
            # Get notes for this phrase
            phrase_notes = []
            for idx in range(start_idx, end_idx + 1):
                if idx in note_by_index:
                    phrase_notes.append(note_by_index[idx])

            phrase_length = len(phrase_notes)

            # Filter by length
            if phrase_length < MIN_PHRASE_LENGTH or phrase_length > MAX_PHRASE_LENGTH:
                skipped_length += 1
                continue

            # Get chords for this phrase
            phrase_chords = get_chords_for_phrase(all_chords, phrase_notes)

            # Convert to intervals
            intervals = notes_to_intervals(phrase_notes)
            durations = notes_to_durations(phrase_notes)

            # Create source ID
            source_id = f"wjd:{melid}:{start_idx}-{end_idx}"

            # Convert chords to relative format
            relative_chords = chords_to_relative(phrase_chords, phrase_notes, info["key"])

            # Get starting bar number from first note
            start_bar = phrase_notes[0].bar if phrase_notes else None

            phrase_data = {
                "intervals": intervals,
                "durations": durations,
                "sourceId": source_id,
                "chords": relative_chords,
                "metadata": {
                    "performer": info["performer"],
                    "title": info["title"],
                    "key": info["key"],
                    "startBar": start_bar
                }
            }

            phrases_by_length[phrase_length].append(phrase_data)
            total_phrases += 1

    print(f"Extracted {total_phrases} phrases")
    print(f"Skipped {skipped_length} phrases (outside length range {MIN_PHRASE_LENGTH}-{MAX_PHRASE_LENGTH})")

    # Convert to output format
    output = {
        "phrasesByLength": {str(k): v for k, v in sorted(phrases_by_length.items())}
    }

    return output


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, OUTPUT_PATH)

    # Ensure output directory exists
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    conn = get_connection()
    try:
        phrases = extract_phrases(conn)

        # Write output
        with open(output_path, 'w') as f:
            json.dump(phrases, f, indent=2)

        print(f"Wrote output to {output_path}")

        # Print summary by length
        print("\nPhrases by length:")
        for length, phrase_list in sorted(phrases["phrasesByLength"].items(), key=lambda x: int(x[0])):
            print(f"  {length} notes: {len(phrase_list)} phrases")

    finally:
        conn.close()


if __name__ == "__main__":
    main()
