#!/usr/bin/env python3
"""Озвучка сцен видео: video/narration.json → video-out/work/voice/<product>-<lang>-<scene>.wav (48 кГц, моно).

Голоса — движки из BMK (tools/voice в BMK/19-21): RU — Silero v5_5_ru (лицензия CC BY-NC 4.0),
EN — Piper en_US-kristin-medium (модель MIT). Диктор и темп — в narration.json, раздел "_voice".
Запуск окружением с torch и piper-tts:
  ~/Desktop/WWWWW/MODS/video-out/voice-venv/bin/python video/voice.py [guard|shield ...] [en|ru ...]
Модели: ~/Desktop/WWWWW/MODS/video-out/voice-models/{piper,silero}.
"""
import array
import json
import sys
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = Path.home() / "Desktop/WWWWW/MODS/video-out"
MODELS = OUT / "voice-models"
DEST = OUT / "work" / "voice"
SR = 48000


def piper(text, cfg):
    from piper import PiperVoice, SynthesisConfig
    if not hasattr(piper, "v"):
        piper.v = PiperVoice.load(str(MODELS / "piper" / "en_US-kristin-medium.onnx"))
    a, sr = array.array("h"), 22050
    for chunk in piper.v.synthesize(text, syn_config=SynthesisConfig(**cfg)):
        a.frombytes(chunk.audio_int16_bytes)
        sr = chunk.sample_rate
    return a, sr


def silero(text, cfg):
    import torch
    if not hasattr(silero, "m"):
        imp = torch.package.PackageImporter(str(MODELS / "silero" / "v5_5_ru.pt"))
        silero.m = imp.load_pickle("tts_models", "model")
        silero.m.to(torch.device("cpu"))
    ssml = f'<speak><prosody rate="{cfg.get("rate", "medium")}">{text}</prosody></speak>'
    audio = silero.m.apply_tts(ssml_text=ssml, speaker=cfg.get("speaker", "aidar"), sample_rate=SR,
                               put_accent=True, put_yo=True)
    a = array.array("h")
    a.frombytes((audio.clamp(-1, 1) * 32767).round().to(torch.int16).numpy().tobytes())
    return a, SR


def main():
    texts = json.loads((HERE / "narration.json").read_text(encoding="utf-8"))
    products = [a for a in sys.argv[1:] if a in ("guard", "shield")] or ["guard", "shield"]
    langs = [a for a in sys.argv[1:] if a in ("en", "ru")] or ["en", "ru"]
    DEST.mkdir(parents=True, exist_ok=True)
    for product in products:
      for lang in langs:
        cfg = texts.get("_voice", {}).get(lang, {})
        for scene, text in texts[product][lang].items():
            samples, sr = (piper if lang == "en" else silero)(text, cfg)
            path = DEST / f"{product}-{lang}-{scene}.wav"
            with wave.open(str(path), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(sr)
                w.writeframes(samples.tobytes())
            print(f"{path.name}: {len(samples) / sr:.1f} с")


if __name__ == "__main__":
    main()
