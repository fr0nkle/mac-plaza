#!/usr/bin/env python3
"""Trim real playlist recordings into arrival cues. Requires Python 3.12+.

Inputs are stereo PCM16 WAVs decoded from the Startup and Mii Maker Loading
recordings listed in Resources/Audio/SOURCE.txt. No synthesis or pitch changes.
Example: python3.12 scripts/prepare-arrival-sounds.py startup.wav loading.wav
"""
import argparse
import array
from pathlib import Path
import sys
import wave

DESTINATION = Path(__file__).resolve().parent.parent / "Sources/MacPlaza/Resources/Audio"


def excerpt(source, name, duration, fade_out):
    with wave.open(str(source), "rb") as recording:
        if recording.getnchannels() != 2 or recording.getsampwidth() != 2:
            raise ValueError("Input must be stereo PCM16 WAV")
        rate = recording.getframerate()
        frames = round(duration * rate)
        samples = array.array("h", recording.readframes(frames))
        if sys.byteorder != "little":
            samples.byteswap()
        if len(samples) != frames * 2:
            raise ValueError("Recording is shorter than the requested excerpt")
    peak = max(abs(value) for value in samples)
    if peak == 0:
        raise ValueError("Recording is silent")
    gain = 0.72 * 32767 / peak
    for frame in range(frames):
        # Tiny attack avoids a cut click; longer release ends the musical phrase.
        envelope = min(1, frame / (rate * 0.005), (frames - 1 - frame) / (rate * fade_out))
        for channel in range(2):
            index = frame * 2 + channel
            samples[index] = round(samples[index] * gain * envelope)
    if sys.byteorder != "little":
        samples.byteswap()
    with wave.open(str(DESTINATION / (name + ".wav")), "wb") as output:
        output.setparams((2, 2, rate, 0, "NONE", "not compressed"))
        output.writeframes(samples.tobytes())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("startup", type=Path)
    parser.add_argument("loading", type=Path)
    arguments = parser.parse_args()
    excerpt(arguments.startup, "arrival-drop", 0.95, 0.12)
    excerpt(arguments.loading, "arrival-wave", 2.8, 0.25)
