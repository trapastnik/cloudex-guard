#!/usr/bin/env python3
"""Видео-эксплейнер Cloudex Guard: YouTube (1920×1080) и вертикаль для соцсетей (1080×1920), EN и RU.

Кадры-титры — video/scenes.html (снимает headless Chrome), записи — assets/demo.mp4 (чаты, 🧹) и
assets/guard.mp4 (страж сети), обе сняты в демо-режиме приложения. Озвучка — video/voice.py
(work/voice/<lang>-<scene>.wav); сцена длится столько, сколько звучит её реплика. Без озвучки — тишина.

  /usr/bin/python3 video/build.py [en|ru ...] [h|v ...]
Готовые файлы: ~/Desktop/WWWWW/MODS/video-out/cloudex-guard-<lang>-<youtube|vertical>.mp4
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
# Где лежит запись в кадре с подписью: (x, y, ширина, высота) для demo.mp4 (442×514) и guard.mp4 (798×514).
PLACE = {
    "h": {"demo": (642, 300, 636, 740), "guard": (386, 300, 1148, 740)},
    "v": {"demo": (60, 640, 960, 1116), "guard": (40, 878, 1000, 644)},
}
# Сюжет: титры (сцена, секунды) и куски записей (кадр с подписью, файл, начало, конец).
STORY = [
    ("card", "hook", 3.0),
    ("card", "p1", 4.0),
    ("card", "fix1", 4.0),
    ("demo", "d1a", "demo", 0.0, 4.5),
    ("demo", "d1b", "demo", 4.5, 10.9),
    ("demo", "d1c", "demo", 10.9, 15.4),
    ("card", "p2", 4.0),
    ("demo", "d2a", "guard", 0.0, 4.1),
    ("demo", "d2b", "guard", 4.1, 9.05),
    ("demo", "d2c", "guard", 9.05, 13.95),
    ("card", "trust", 3.0),
    ("card", "cta", 4.0),
]
FADE = 0.18
DEMO_SPEED = 1.25   # записи демо чуть быстрее — в ритм речи
VOICE_DELAY = 0.12   # реплика начинается почти сразу
VOICE_TAIL = 0.28    # и после неё короткая пауза
ZOOM = 0.035         # наезд камеры на титрах за сцену


def voice(lang, scene):
    path = WORK / "voice" / f"{lang}-{scene}.wav"
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
    png = WORK / f"{lang}-{fmt}-{scene}.png"
    run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-color-profile=srgb",
         "--allow-file-access-from-files", f"--window-size={w},{h}", f"--screenshot={png}",
         f"{SCENES.as_uri()}?s={scene}&l={lang}&f={fmt}"])
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
         "-ss", f"{t0}", "-t", f"{src_span}", "-i", str(ROOT / "assets" / f"{clip}.mp4"), *ain,
         "-filter_complex",
         f"[1:v]setpts=(PTS-STARTPTS)/{DEMO_SPEED},fps={FPS},scale={w}:{h}:flags=lanczos{pad}[c];"
         f"[0:v]fps={FPS}[b];[b][c]overlay={x}:{y}:eof_action=repeat,format=yuv420p{tail}[v];" + af.format(n=2),
         "-map", "[v]", "-map", "[a]", "-t", f"{dur}",
         "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-ar", "48000",
         str(out)])


# Короткая версия для Reels/TikTok (~30 с): зацепка → карта контекста → 🧹 → заморозка → возврат → ссылка.
SHORT = [
    ("card", "hook", 3.0),
    ("demo", "d1a", "demo", 0.0, 4.5),
    ("demo", "d1c", "demo", 10.9, 15.4),
    ("demo", "d2b", "guard", 4.1, 9.05),
    ("demo", "d2c", "guard", 9.05, 13.95),
    ("card", "cta", 3.5),
]


def build(lang, fmt, story=None, suffix=None):
    STORY = story or globals()["STORY"]
    parts = []
    for i, item in enumerate(STORY):
        out = WORK / f"{lang}-{fmt}{suffix or ''}-{i:02d}.mp4"
        if item[0] == "card":
            _, scene, dur = item
            wav, length = voice(lang, scene)
            card(shot(scene, lang, fmt), max(dur, VOICE_DELAY + length + VOICE_TAIL), out, wav)
        else:
            _, scene, clip, t0, t1 = item
            prev = STORY[i - 1] if i else None
            nxt = STORY[i + 1] if i + 1 < len(STORY) else None
            first = not prev or prev[0] != "demo" or prev[2] != clip
            last = not nxt or nxt[0] != "demo" or nxt[2] != clip
            wav, length = voice(lang, scene)
            demo(shot(scene, lang, fmt), clip, t0, t1, PLACE[fmt][clip], out, first, last,
                 wav, VOICE_DELAY + length + VOICE_TAIL)
        parts.append(out)
    lst = WORK / f"{lang}-{fmt}{suffix or ''}.txt"
    lst.write_text("".join(f"file '{p}'\n" for p in parts))
    name = OUT / f"cloudex-guard-{lang}-{suffix.strip('-') if suffix else ('youtube' if fmt == 'h' else 'vertical')}.mp4"
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(lst),
         "-c:v", "libx264", "-crf", "20", "-preset", "slow", "-pix_fmt", "yuv420p", "-r", str(FPS),
         "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-c:a", "aac", "-b:a", "160k", "-ar", "48000",
         "-movflags", "+faststart", str(name)])
    print("готово:", name)


if __name__ == "__main__":
    langs = [a for a in sys.argv[1:] if a in ("en", "ru")] or ["en", "ru"]
    fmts = [a for a in sys.argv[1:] if a in ("h", "v")] or ["h", "v"]
    if "short" in sys.argv[1:]:  # только короткая вертикаль: video/build.py short [en|ru]
        WORK.mkdir(parents=True, exist_ok=True)
        for lang in langs:
            build(lang, "v", SHORT, "-short")
        sys.exit(0)
    WORK.mkdir(parents=True, exist_ok=True)
    for lang in langs:
        for fmt in fmts:
            build(lang, fmt)
