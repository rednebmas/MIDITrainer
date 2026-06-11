"""Fit a power-law learning curve to practice history and project it forward.

Usage: project_improvement.py <miditrainer.sqlite> <output_dir> <extra_days> [since]

Pass since=2026-01-01 to fit only the BPM-100 era; the difficulty adjustment
cannot account for the slower December tempo.
"""

import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from history_data import adjusted_accuracy, first_guesses, load_attempts

COLORS = {"novel": "#228833", "adjusted": "#4477aa"}


def binned_error(x_positions, correct, n_bins=8):
    """Error rate per equal-count bin of cumulative practice position."""
    bins = pd.qcut(x_positions, n_bins, labels=False)
    g = pd.DataFrame({"x": x_positions, "ok": correct}).groupby(bins)
    return g["x"].mean(), 1 - g["ok"].mean(), g.size()


def fit_power_law(x, err, weights):
    """log(err) = c - b*log(x); returns (b, c, se_b)."""
    coef, cov = np.polyfit(np.log(x), np.log(err), 1,
                           w=np.sqrt(np.asarray(weights, dtype=float)), cov=True)
    return -coef[0], coef[1], np.sqrt(cov[0][0])


def series_for_projection(firsts):
    f = firsts.sort_values("timestamp").reset_index(drop=True)
    novel = f[f["ask_no"] == 0]
    yield "novel", "brand-new melodies", binned_error(
        novel.index.to_series() + 1, novel["isCorrect"])
    fi = f.dropna(subset=["expectedInterval"]).copy()
    fi["bin"] = pd.qcut(fi.index.to_series(), 8, labels=False)
    adj = adjusted_accuracy(fi, "bin").set_index("key")
    x = fi.groupby("bin").apply(lambda s: s.index.to_series().mean() + 1)
    yield "adjusted", "all melodies, difficulty-adjusted", (
        x, 1 - adj["adjusted"], adj["n"])


def plot_series(ax, key, label, data, n_future, extra_days):
    x, err, n = data
    b, c, se = fit_power_law(x, err, n)
    ax.scatter(x, 1 - err, s=n / 4, color=COLORS[key], alpha=0.6)
    grid = np.geomspace(float(x.iloc[0]), n_future, 200)
    ax.plot(grid, 1 - np.exp(c) * grid ** -b, color=COLORS[key], lw=2,
            label=f"{label} (fit b={b:.2f})")
    band = [1 - np.exp(c + s * np.log(grid / x.mean())) * grid ** -b for s in (se, -se)]
    ax.fill_between(grid, np.minimum(*band), np.maximum(*band),
                    color=COLORS[key], alpha=0.12)
    central = lambda nn, s=0.0: 1 - np.exp(c + s * np.log(nn / x.mean())) * nn ** -b
    lo, hi = sorted([central(n_future, se), central(n_future, -se)])
    now = central(float(x.iloc[-1]))
    print(f"{label}: now={now:.1%} -> in {extra_days}d of daily practice="
          f"{central(n_future):.1%} (range {lo:.1%}-{hi:.1%}, b={b:.2f}±{se:.2f})")


def project(firsts, per_day, extra_days, out):
    n_now = len(firsts)
    n_future = n_now + per_day * extra_days
    fig, ax = plt.subplots(figsize=(11, 6))
    for key, label, data in series_for_projection(firsts):
        plot_series(ax, key, label, data, n_future, extra_days)
    for nn, name in [(n_now, "today"), (n_future, f"+{extra_days} days of daily practice")]:
        ax.axvline(nn, color="gray", ls=":", lw=1)
        ax.annotate(name, (nn, 0.02), xycoords=("data", "axes fraction"),
                    rotation=90, va="bottom", ha="right", fontsize=8, color="gray")
    ax.set_xscale("log")
    ax.yaxis.set_major_formatter(lambda v, _: f"{v:.0%}")
    ax.set_xlabel("Cumulative notes practiced (first guesses, log scale)")
    ax.set_ylabel("First-guess accuracy")
    ax.set_title("Power-law learning curve, projected through "
                 f"{extra_days} days of daily practice (~{per_day:.0f} notes/day)")
    ax.grid(alpha=0.25)
    ax.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(out / "6_projection.png", dpi=150)
    return n_now, n_future


def main(db_path, out_dir, extra_days, since=None):
    df = load_attempts(db_path)
    firsts = first_guesses(df)
    if since:
        firsts = firsts[firsts["when"] >= pd.Timestamp(since)]
    days = (df["when"].max() - df["when"].min()).days + 1
    per_session = len(first_guesses(df)) / df["sessionId"].nunique()
    n_now, n_future = project(firsts, per_session, extra_days, Path(out_dir))
    novel_perfect = firsts[firsts["ask_no"] == 0].groupby("sequenceId")["isCorrect"].all()
    print(f"\nnovel melodies currently perfect on first listen: {novel_perfect.mean():.1%} "
          f"(n={len(novel_perfect)})")
    print(f"history: {days} calendar days, {df['sessionId'].nunique()} sessions, "
          f"{n_now} first-guess notes since {since or 'start'} ({per_session:.0f}/session)")
    print(f"daily practice -> one session/day -> cumulative {n_now} -> {n_future:.0f} notes")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]),
         sys.argv[4] if len(sys.argv) > 4 else None)
