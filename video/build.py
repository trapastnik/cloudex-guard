#!/usr/bin/env python3
"""Видео-эксплейнеры Cloudex Guard и Cloudex Shield: YouTube (1920×1080), вертикаль (1080×1920)
и короткая вертикаль (~30 с), EN и RU.

Кадры-титры — video/scenes.html (снимает headless Chrome). Записи сняты в демо-режиме приложений:
Guard — assets/demo.mp4 (чаты, 🧹, zsh app/demo.sh), Shield — ../shield/assets/demo.mp4 (страж сети,
zsh ../shield/app/demo.sh). Озвучка — video/voice.py (work/voice/<product>-<lang>-<scene>.wav); сцена
длится столько, сколько звучит её реплика. Без озвучки — тишина.

  /usr/bin/python3 video/build.py guard|shield [en|ru ...] [h|v ...] [short]
Готовые файлы: ~/Desktop/WWWWW/MODS/video-out/cloudex-<product>-<lang>-<youtube|vertical|short>.mp4
Точки разреза записей (CUTS) подобраны под конкретную запись — после перезаписи поправить.
"""
import subprocess
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCENES = ROOT / "video" / "scenes.html"
OUT = Path.home() / "Desktop/WWWWW/MODS/video-out"
WORK = OUT / "work"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FPS = 30

SIZE = {"h": (1920, 1080), "v": (1080, 1920)}
# Записи: файл и где он стоит в кадре с подписью — (x, y, ширина, высота). Запись меню
# Guard — 490×454, широкая Shield (меню и подменю «Защита» слева) — около 798×514.
CLIPS = {
    "guard": ROOT / "assets" / "demo.mp4",
    "shield": ROOT.parent / "shield" / "assets" / "demo.mp4",
}
PLACE = {
    "h": {"guard": (561, 300, 798, 740), "shield": (386, 300, 1148, 740)},
    "v": {"guard": (60, 700, 960, 890), "shield": (40, 878, 1000, 644)},
}
# Сюжеты: титры (сцена, секунды) и куски записи (сцена с подписью, начало, конец в секундах записи).
STORIES = {
    "guard": [
        ("card", "hook", 3.0),
        ("card", "p1", 4.0),
        ("card", "fix1", 4.0),
        ("demo", "d1a", 0.0, 6.0),
        ("demo", "d1b", 6.0, 16.4),
        ("demo", "d1c", 16.4, 22.2),
        ("card", "trust", 3.0),
        ("card", "cta", 4.0),
    ],
    "shield": [
        ("card", "hook", 3.0),
        ("card", "p2", 4.0),
        ("demo", "d2a", 0.0, 4.1),
        ("demo", "d2b", 4.1, 9.05),
        ("demo", "d2c", 9.05, 13.95),
        ("card", "trust", 3.0),
        ("card", "cta", 4.0),
    ],
}
# Короткие версии для Shorts/Reels/Клипов (~30 с).
SHORTS = {
    "guard": [("card", "hook", 3.0), ("demo", "d1a", 0.0, 6.0), ("demo", "d1b", 6.0, 16.4),
              ("demo", "d1c", 16.4, 22.2), ("card", "cta", 3.5)],
    "shield": [("card", "hook", 3.0), ("demo", "d2a", 0.0, 4.1), ("demo", "d2b", 4.1, 9.05),
               ("demo", "d2c", 9.05, 13.95), ("card", "cta", 3.5)],
}
PRODUCT = "guard"
FADE = 0.18
DEMO_SPEED = 1.25   # записи демо чуть быстрее — в ритм речи
VOICE_DELAY = 0.12   # реплика начинается почти сразу
VOICE_TAIL = 0.28    # и после неё короткая пауза
ZOOM = 0.035         # наезд камеры на титрах за сцену


def voice(lang, scene):
    path = WORK / "voice" / f"{PRODUCT}-{lang}-{scene}.wav"
    if not path.exists():
        return None, 0.0
    with wave.open(str(path)) as w:
        return path, w.getnframes() / w.getframerate()


def audio_args(wav, dur):
    """Входы и фильтр звука для куска длиной dur: реплика с задержкой, дальше тишина."""
    if wav:
        ms = int(VOICE_DELAY * 1000)
        return ["-i", str(wav)], f"[{{n}}:a]aresample=48000,adelay={ms}:all=1,apad,atrim=0:{dur:.3f},aformat=channel_layouts=stereo[a]"
    return ["-f", "lavfi", "-t", f"{dur:.3f}", "-i", "anullsrc=r=48000:cl=stereo"], "[{n}:a]anull[a]"


def run(args):
    subprocess.run(args, check=True)


SIZE_OF = {}


def shot(scene, lang, fmt):
    w, h = SIZE[fmt]
    png = WORK / f"{PRODUCT}-{lang}-{fmt}-{scene}.png"
    run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-color-profile=srgb",
         "--allow-file-access-from-files", f"--window-size={w},{h}", f"--screenshot={png}",
         f"{SCENES.as_uri()}?p={PRODUCT}&s={scene}&l={lang}&f={fmt}"])
    SIZE_OF[str(png)] = (w, h)
    return png


def fades(dur):
    return f"fade=in:st=0:d={FADE},fade=out:st={dur - FADE:.3f}:d={FADE}"


def card(png, dur, out, wav=None):
    ain, af = audio_args(wav, dur)
    run(["ffmpeg", "-v", "error", "-y", "-loop", "1", "-t", f"{dur}", "-i", str(png), *ain,
         "-filter_complex",
         f"[0:v]fps={FPS},scale=w='trunc(iw*(1+{ZOOM}*t/{dur:.3f})/2)*2':h=-2:eval=frame,"
         f"crop={SIZE_OF[str(png)][0]}:{SIZE_OF[str(png)][1]},format=yuv420p,{fades(dur)}[v];" + af.format(n=1),
         "-map", "[v]", "-map", "[a]", "-t", f"{dur}",
         "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-ar", "48000",
         str(out)])


def demo(png, clip, t0, t1, place, out, first, last, wav=None, dur=None):
    x, y, w, h = place
    src_span = t1 - t0
    span = src_span / DEMO_SPEED
    dur = max(span, dur or 0)
    hold = dur - span  # реплика длиннее куска записи — держим последний кадр
    vf = []
    if first:
        vf.append(f"fade=in:st=0:d={FADE}")
    if last:
        vf.append(f"fade=out:st={dur - FADE:.3f}:d={FADE}")
    tail = ("," + ",".join(vf)) if vf else ""
    ain, af = audio_args(wav, dur)
    pad = f",tpad=stop_mode=clone:stop_duration={hold:.3f}" if hold > 0 else ""
    run(["ffmpeg", "-v", "error", "-y", "-loop", "1", "-t", f"{dur}", "-i", str(png),
         "-ss", f"{t0}", "-t", f"{src_span}", "-i", str(CLIPS[clip]), *ain,
         "-filter_complex",
         f"[1:v]setpts=(PTS-STARTPTS)/{DEMO_SPEED},fps={FPS},scale={w}:{h}:flags=lanczos{pad}[c];"
         f"[0:v]fps={FPS}[b];[b][c]overlay={x}:{y}:eof_action=repeat,format=yuv420p{tail}[v];" + af.format(n=2),
         "-map", "[v]", "-map", "[a]", "-t", f"{dur}",
         "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-ar", "48000",
         str(out)])


def build(lang, fmt, story, suffix=None):
    parts = []
    for i, item in enumerate(story):
        out = WORK / f"{PRODUCT}-{lang}-{fmt}{suffix or ''}-{i:02d}.mp4"
        if item[0] == "card":
            _, scene, dur = item
            wav, length = voice(lang, scene)
            card(shot(scene, lang, fmt), max(dur, VOICE_DELAY + length + VOICE_TAIL), out, wav)
        else:
            _, scene, t0, t1 = item
            first = i == 0 or story[i - 1][0] != "demo"
            last = i + 1 == len(story) or story[i + 1][0] != "demo"
            wav, length = voice(lang, scene)
            demo(shot(scene, lang, fmt), PRODUCT, t0, t1, PLACE[fmt][PRODUCT], out, first, last,
                 wav, VOICE_DELAY + length + VOICE_TAIL)
        parts.append(out)
    lst = WORK / f"{PRODUCT}-{lang}-{fmt}{suffix or ''}.txt"
    lst.write_text("".join(f"file '{p}'\n" for p in parts))
    kind = suffix.strip('-') if suffix else ('youtube' if fmt == 'h' else 'vertical')
    name = OUT / f"cloudex-{PRODUCT}-{lang}-{kind}.mp4"
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(lst),
         "-c:v", "libx264", "-crf", "20", "-preset", "slow", "-pix_fmt", "yuv420p", "-r", str(FPS),
         "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-c:a", "aac", "-b:a", "160k", "-ar", "48000",
         "-movflags", "+faststart", str(name)])
    print("готово:", name)


if __name__ == "__main__":
    args = sys.argv[1:]
    PRODUCT = next((a for a in args if a in STORIES), None) or sys.exit("укажите guard или shield")
    if not CLIPS[PRODUCT].exists():
        sys.exit(f"нет записи {CLIPS[PRODUCT]} — снимите её демо-скриптом приложения")
    langs = [a for a in args if a in ("en", "ru")] or ["en", "ru"]
    fmts = [a for a in args if a in ("h", "v")] or ["h", "v"]
    WORK.mkdir(parents=True, exist_ok=True)
    for lang in langs:
        if "short" in args:
            build(lang, "v", SHORTS[PRODUCT], "-short")
            continue
        for fmt in fmts:
            build(lang, fmt, STORIES[PRODUCT])
