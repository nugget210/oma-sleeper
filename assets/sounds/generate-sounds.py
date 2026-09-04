#!/usr/bin/env python3
"""Generate the short alert tones used by the score-alert setting.

Each sound is a synthesized sine envelope written as 16-bit mono PCM, so the
plugin ships small, dependency-free audio that any PipeWire/ALSA player can
handle. Run this script to regenerate the .wav files next to it in place.
"""

import math
import os
import struct
import wave

RATE = 44100
AMPLITUDE = 0.32
ATTACK_SECONDS = 0.004


def add_tone(frames, start_seconds, frequency, duration, decay, gain=1.0, harmonic=0.0):
    """Mix one exponentially decaying sine (plus optional octave) into frames."""
    attack = max(1, int(ATTACK_SECONDS * RATE))
    start = int(start_seconds * RATE)
    for index in range(int(duration * RATE)):
        position = start + index
        if position >= len(frames):
            break
        ramp = index / attack if index < attack else math.exp(-(index - attack) / (decay * RATE))
        angle = 2 * math.pi * frequency * index / RATE
        value = math.sin(angle) + harmonic * math.sin(2 * angle)
        frames[position] += AMPLITUDE * gain * ramp * value


def write_wave(name, seconds, voices):
    frames = [0.0] * int(seconds * RATE)
    for voice in voices:
        add_tone(frames, *voice)
    payload = b"".join(
        struct.pack("<h", max(-32767, min(32767, int(sample * 32767)))) for sample in frames
    )
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), name)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(payload)
    print(f"wrote {path} ({len(payload) + 44} bytes)")


# Scoring tones, one of which the user selects. (start, freq, duration, decay, gain, harmonic)
write_wave("ding.wav", 0.30, [(0.0, 880.0, 0.30, 0.085, 1.0, 0.18)])
write_wave("chime.wav", 0.38, [(0.0, 784.0, 0.20, 0.070, 0.9, 0.12),
                               (0.13, 1175.0, 0.25, 0.080, 0.9, 0.12)])
write_wave("blip.wav", 0.12, [(0.0, 1046.0, 0.12, 0.028, 1.0, 0.30)])

# Lead-change tones. Three notes rather than one or two, so a lead change is
# never mistaken for whichever scoring tone is selected. C-E-A rising for taking
# the lead, the same notes falling for losing it.
write_wave("lead-up.wav", 0.50, [(0.00, 523.0, 0.16, 0.060, 0.85, 0.10),
                                 (0.12, 659.0, 0.16, 0.060, 0.90, 0.10),
                                 (0.24, 880.0, 0.26, 0.090, 1.00, 0.14)])
write_wave("lead-down.wav", 0.50, [(0.00, 880.0, 0.16, 0.060, 0.90, 0.10),
                                   (0.12, 659.0, 0.16, 0.060, 0.85, 0.10),
                                   (0.24, 523.0, 0.26, 0.090, 0.85, 0.14)])
