#!/usr/bin/env python3
"""Образцы голосов для выбора: одна фраза разными дикторами и темпами → video-out/samples/*.mp3.

  ~/Desktop/WWWWW/MODS/video-out/voice-venv/bin/python video/samples.py
"""
import array
import subprocess
import wave
from pathlib import Path

OUT = Path.home() / "Desktop/WWWWW/MODS/video-out"
MODELS = OUT / "voice-models"
DEST = OUT / "samples"

RU = "Ведёте десять чатов Клод Код одновременно? Контекст переполняется, лимиты тают! Клаудекс Гард решает это одной кнопкой."
EN = "Running ten Claude Code chats at once? Your context fills up and your limits melt! Cloudex Guard fixes that in one click."


def save(name, samples, sr):
    DEST.mkdir(parents=True, exist_ok=True)
    wav = DEST / f"{name}.wav"
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(samples.tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-b:a", "128k", str(wav.with_suffix(".mp3"))], check=True)
    wav.unlink()
    print(wav.with_suffix(".mp3").name)


def silero_samples():
    import torch
    imp = torch.package.PackageImporter(str(MODELS / "silero" / "v5_5_ru.pt"))
    m = imp.load_pickle("tts_models", "model")
    m.to(torch.device("cpu"))
    for speaker in ("aidar", "eugene", "xenia", "baya"):
        for rate in ("medium", "fast"):
            ssml = f'<speak><prosody rate="{rate}">{RU}</prosody></speak>'
            audio = m.apply_tts(ssml_text=ssml, speaker=speaker, sample_rate=48000, put_accent=True, put_yo=True)
            a = array.array("h")
            a.frombytes((audio.clamp(-1, 1) * 32767).round().to(torch.int16).numpy().tobytes())
            save(f"ru-{speaker}-{rate}", a, 48000)


def piper_samples():
    from piper import PiperVoice, SynthesisConfig
    v = PiperVoice.load(str(MODELS / "piper" / "en_US-kristin-medium.onnx"))
    for name, cfg in (("calm", SynthesisConfig(length_scale=0.96)),
                      ("brisk", SynthesisConfig(length_scale=0.86, noise_scale=0.75, noise_w_scale=0.9)),
                      ("fast", SynthesisConfig(length_scale=0.8, noise_scale=0.8, noise_w_scale=1.0))):
        a, sr = array.array("h"), 22050
        for chunk in v.synthesize(EN, syn_config=cfg):
            a.frombytes(chunk.audio_int16_bytes)
            sr = chunk.sample_rate
        save(f"en-kristin-{name}", a, sr)


if __name__ == "__main__":
    silero_samples()
    piper_samples()
