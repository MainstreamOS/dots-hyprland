#!/usr/bin/env python3
"""
voice-recorder.py - Records audio from default microphone to an AAC .m4a file.
Used by PhoneVoiceRecorder.qml for voice notes.
Outputs:
  RECORDING:<seconds>
  DONE:<path>
  CANCELLED
  ERROR:<message>
"""
import os
import shutil
import sys
import time
import signal
import subprocess

from phone_runtime import VOICE_NOTES

output_file = ""
proc = None
handled = False

def finish(success=True):
    global handled, proc, output_file
    if handled:
        return
    handled = True
    if proc and proc.poll() is None:
        try:
            proc.send_signal(signal.SIGINT)
            proc.wait(timeout=3.0)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass

    if success and output_file and os.path.exists(output_file) and os.path.getsize(output_file) > 100:
        sys.stdout.write("DONE:" + output_file + "\n")
        sys.stdout.flush()
        sys.exit(0)
    else:
        if output_file and os.path.exists(output_file):
            try:
                os.remove(output_file)
            except Exception:
                pass
        sys.stdout.write("CANCELLED\n")
        sys.stdout.flush()
        sys.exit(0)

signal.signal(signal.SIGINT, lambda s, f: finish(True))
signal.signal(signal.SIGTERM, lambda s, f: finish(True))

def main():
    global output_file, proc
    cache_dir = str(VOICE_NOTES)
    os.makedirs(cache_dir, exist_ok=True)

    ts = int(time.time() * 1000)
    output_file = os.path.join(cache_dir, f"voice_{ts}.m4a")

    recorders = [
        ["ffmpeg", "-y", "-f", "pulse", "-i", "default", "-c:a", "aac", "-b:a", "128k", output_file],
        ["pw-record", "--channels", "1", "--rate", "48000", output_file.replace(".m4a", ".ogg")]
    ]

    selected_cmd = None
    for cmd in recorders:
        bin_name = cmd[0]
        if shutil.which(bin_name):
            selected_cmd = cmd
            if bin_name == "pw-record":
                output_file = output_file.replace(".m4a", ".ogg")
            break

    if not selected_cmd:
        sys.stdout.write("ERROR:No recording utility found (ffmpeg or pw-record)\n")
        sys.stdout.flush()
        sys.exit(1)

    try:
        proc = subprocess.Popen(
            selected_cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
    except Exception as e:
        sys.stdout.write(f"ERROR:Failed to start recording: {e}\n")
        sys.stdout.flush()
        sys.exit(1)

    start_time = time.time()
    try:
        while not handled:
            sys.stdout.write(f"RECORDING:{int(time.time() - start_time)}\n")
            sys.stdout.flush()
            try:
                proc.wait(timeout=1)
                break
            except subprocess.TimeoutExpired:
                pass
    except KeyboardInterrupt:
        pass

    finish(True)

if __name__ == "__main__":
    main()
