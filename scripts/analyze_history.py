"""Chart improvement metrics from MIDITrainer practice history.

Usage: analyze_history.py <miditrainer.sqlite> <output_dir>
"""

import math
import sys
from pathlib import Path

import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import pandas as pd

from history_data import (adjusted_accuracy, first_guesses, load_attempts,
                          melody_stats, response_times)

EVENTS = [
    ("2026-01-01", "BPM 80→100"),
    ("2026-02-02", "random→songs"),
    ("2026-04-13", "key E→D"),
    ("2026-05-11", "key D→G"),
]
COLORS = {"random melodies": "#4477aa", "real songs": "#ee7733"}
INTERVAL_NAMES = ["U", "m2", "M2", "m3", "M3", "P4", "TT", "P5", "m6", "M6", "m7", "M7", "8ve"]


def annotate_events(ax):
    for date, label in EVENTS:
        x = pd.Timestamp(date)
        ax.axvline(x, color="gray", ls=":", lw=1, alpha=0.7)
        ax.annotate(label, (x, 0.02), xycoords=("data", "axes fraction"),
                    rotation=90, va="bottom", ha="right", fontsize=8, color="gray")


def by_period(df, value_col, freq, agg="mean", min_n=80):
    g = df.set_index("when").groupby([pd.Grouper(freq=freq), "source"])[value_col]
    out = g.agg(value=agg, count="count").reset_index()
    return out[out["count"] >= min_n]


def style_time_axis(ax):
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %Y"))
    ax.grid(alpha=0.25)


def percent_axis(ax):
    ax.yaxis.set_major_formatter(lambda v, _: f"{v:.0%}")


def plot_by_source(ax, data, ylabel):
    for src, sub in data.groupby("source"):
        ax.plot(sub["when"], sub["value"], "o-", color=COLORS[src], label=src, ms=5)
    annotate_events(ax)
    style_time_axis(ax)
    ax.set_ylabel(ylabel)
    ax.legend(loc="lower right")


def fig_novel_accuracy(firsts, out):
    fig, ax = plt.subplots(figsize=(11, 5.5))
    novel = firsts[firsts["ask_no"] == 0]
    monthly = by_period(novel, "isCorrect", "MS", min_n=40)
    plot_by_source(ax, monthly, "First-guess accuracy")
    for _, r in monthly.iterrows():
        ax.annotate(f"n={r['count']}", (r["when"], r["value"]), fontsize=7,
                    textcoords="offset points", xytext=(0, 8), ha="center", color="#555")
    percent_axis(ax)
    ax.set_title("Sight-unheard: first-guess accuracy on never-heard-before melodies\n"
                 "(monthly; after mid-April the app served almost no new melodies)")
    fig.tight_layout()
    fig.savefig(out / "1_novel_melody_accuracy.png", dpi=150)


def fig_learning_curve(firsts, out, window=500):
    fig, ax = plt.subplots(figsize=(11, 5.5))
    f = firsts.sort_values("timestamp").reset_index(drop=True)
    ax.plot(f.index, f["isCorrect"].rolling(window).mean(), color="#999999",
            lw=1.5, label=f"all melodies incl. review queue (rolling {window})")
    novel = f[f["ask_no"] == 0]
    ax.plot(novel.index, novel["isCorrect"].rolling(window // 2).mean(),
            color="#228833", lw=2.2, label=f"never-heard-before only (rolling {window // 2})")
    percent_axis(ax)
    ax.set_xlabel("Cumulative notes practiced (first guesses)")
    ax.set_ylabel("First-guess accuracy")
    ax.set_title("Learning curve: your ear on brand-new melodies keeps climbing,\n"
                 "while the review queue keeps serving you the ones you miss")
    ax.grid(alpha=0.25)
    ax.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(out / "2_learning_curve.png", dpi=150)


def fig_difficulty(firsts, out):
    fig, axes = plt.subplots(2, 1, figsize=(11, 8), sharex=True)
    f = firsts.dropna(subset=["expectedInterval"])
    month = f.set_index("when").groupby(pd.Grouper(freq="MS"))["expectedInterval"]
    diff = month.agg(mean_leap=lambda s: s.abs().mean(),
                     big_leaps=lambda s: (s.abs() > 4).mean())
    axes[0].plot(diff.index, diff["mean_leap"], "o-", color="#aa3377",
                 label="avg interval size (semitones)")
    ax2 = axes[0].twinx()
    ax2.plot(diff.index, diff["big_leaps"], "s--", color="#66ccee",
             label="share of intervals > P4")
    percent_axis(ax2)
    axes[0].set_ylabel("Avg interval size (semitones)", color="#aa3377")
    ax2.set_ylabel("Share of intervals > P4", color="#3399bb")
    axes[0].set_title("The material got harder…")
    axes[0].grid(alpha=0.25)

    adj = adjusted_accuracy(f, pd.Grouper(freq="MS", key="when"))
    axes[1].plot(adj["key"], adj["raw"], "o-", color="#999999", label="raw accuracy")
    axes[1].plot(adj["key"], adj["adjusted"], "o-", color="#228833", lw=2.2,
                 label="difficulty-adjusted accuracy")
    percent_axis(axes[1])
    annotate_events(axes[1])
    style_time_axis(axes[1])
    axes[1].set_ylabel("First-guess accuracy")
    axes[1].set_title("…so flat raw accuracy means a better ear: accuracy holding on a harder mix\n"
                      "(adjusted = reweighted to a constant interval & novel/review mix)")
    axes[1].legend(loc="lower right")
    axes[1].grid(alpha=0.25)
    fig.tight_layout()
    fig.savefig(out / "3_difficulty_adjusted.png", dpi=150)


def fig_melodies(melodies, out):
    fig, axes = plt.subplots(2, 1, figsize=(11, 8), sharex=True)
    plot_by_source(axes[0], by_period(melodies, "perfect", "W", min_n=15),
                   "Perfect first playthroughs")
    percent_axis(axes[0])
    axes[0].set_title("Melodies nailed end-to-end with zero wrong notes, first listen")
    plot_by_source(axes[1], by_period(melodies, "guesses_per_note", "W", min_n=15),
                   "Guesses per note")
    axes[1].set_title("Average guesses needed per note (1.0 = always right first try)")
    fig.tight_layout()
    fig.savefig(out / "4_melody_level.png", dpi=150)


def interval_label(semitones):
    name = INTERVAL_NAMES[abs(int(semitones))]
    arrow = "↑" if semitones > 0 else ("↓" if semitones < 0 else "")
    return f"{arrow}{name}"


def early_late_split(df):
    third = len(df) // 3
    s = df.sort_values("timestamp")
    return s.iloc[:third], s.iloc[-third:]


def grouped_error_bars(ax, early, late, col, labels, min_n=30):
    stats = []
    for value in sorted(set(early[col].dropna()) & set(late[col].dropna())):
        e, l = early[early[col] == value], late[late[col] == value]
        if len(e) >= min_n and len(l) >= min_n:
            stats.append((labels(value), 1 - e["isCorrect"].mean(), 1 - l["isCorrect"].mean()))
    x = range(len(stats))
    ax.bar([i - 0.2 for i in x], [s[1] for s in stats], 0.4,
           label="first 3rd of practice", color="#bbbbbb")
    ax.bar([i + 0.2 for i in x], [s[2] for s in stats], 0.4,
           label="last 3rd of practice (~all review melodies)", color="#228833")
    ax.set_xticks(list(x), [s[0] for s in stats])
    percent_axis(ax)
    ax.set_ylabel("Error rate (first guess)")
    ax.grid(alpha=0.25, axis="y")
    ax.legend()


def fig_intervals(firsts, out):
    early, late = early_late_split(firsts)
    fig, axes = plt.subplots(2, 1, figsize=(12, 9))
    in_range = lambda d: d[d["expectedInterval"].abs() <= 12]
    grouped_error_bars(axes[0], in_range(early), in_range(late), "expectedInterval",
                       interval_label)
    axes[0].set_title("Error rate by melodic interval — early vs late practice")
    grouped_error_bars(axes[1], early, late, "expectedScaleDegree",
                       lambda d: ["1", "2", "3", "4", "5", "6", "7"][int(d) - 1])
    axes[1].set_title("Error rate by scale degree of the target note")
    fig.tight_layout()
    fig.savefig(out / "5_intervals_degrees.png", dpi=150)


def two_proportion_z(k1, n1, k2, n2):
    p1, p2, p = k1 / n1, k2 / n2, (k1 + k2) / (n1 + n2)
    se = math.sqrt(p * (1 - p) * (1 / n1 + 1 / n2))
    return p1, p2, (p2 - p1) / se


def accuracy_shift(label, sub):
    early, late = early_late_split(sub)
    p1, p2, z = two_proportion_z(early["isCorrect"].sum(), len(early),
                                 late["isCorrect"].sum(), len(late))
    print(f"{label}: {p1:.1%} -> {p2:.1%}  (n={len(early)}/{len(late)}, z={z:.1f})")


def print_summary(firsts, rt, melodies):
    print("=== first vs last third of practice ===")
    accuracy_shift("all first guesses", firsts)
    accuracy_shift("never-heard-before melodies", firsts[firsts["ask_no"] == 0])
    f = firsts.dropna(subset=["expectedInterval"])
    adj = adjusted_accuracy(
        f.assign(third=pd.qcut(f["timestamp"], 3, labels=["early", "mid", "late"])),
        "third")
    print(adj.to_string(index=False))
    e, l = early_late_split(f)
    print(f"difficulty: mean |interval| {e['expectedInterval'].abs().mean():.2f} -> "
          f"{l['expectedInterval'].abs().mean():.2f} semitones")
    e, l = early_late_split(rt)
    print(f"median response: {e['dt'].median():.2f}s -> {l['dt'].median():.2f}s")
    m = melodies.assign(timestamp=melodies["when"])
    e, l = early_late_split(m)
    print(f"perfect first playthroughs: {e['perfect'].mean():.1%} -> {l['perfect'].mean():.1%}")
    print(f"guesses per note: {e['guesses_per_note'].mean():.2f} -> {l['guesses_per_note'].mean():.2f}")


def main(db_path, out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    df = load_attempts(db_path)
    firsts = first_guesses(df)
    melodies = melody_stats(df)
    fig_novel_accuracy(firsts, out)
    fig_learning_curve(firsts, out)
    fig_difficulty(firsts, out)
    fig_melodies(melodies, out)
    fig_intervals(firsts, out)
    print_summary(firsts, response_times(df), melodies)
    print(f"\nSaved 5 figures to {out}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
