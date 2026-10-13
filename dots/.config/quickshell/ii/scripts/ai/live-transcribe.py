#!/usr/bin/env python3
# Live dictation through the Gemini Live API.
# Key: GEMINI_API_KEY in the environment only. Output, one per line:
#   TEXT:<full transcript so far>
#   ERROR:<no-key|no-websockets|no-recorder|connect|closed>
# SIGTERM, SIGINT, SIGHUP or EOF on stdin stop the recording; the final words
# are awaited briefly and printed before exiting.
import asyncio
import base64
import ctypes
import json
import os
import shutil
import signal
import sys

ENDPOINT = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent"
# Checked against the Live API docs before release; keep them in this one place.
SETUP = {
    "setup": {
        "model": "models/gemini-3.5-transcribe-live",
        "generationConfig": {"responseModalities": ["TEXT"]},
        "inputAudioTranscription": {"mode": "smart"},
    }
}
CHUNK_SIZE = 3200  # 100 ms at 16 kHz, 16-bit mono
START_FALLBACK = 2.0
FINAL_WAIT = 1.5

RECORDERS = [
    ["pw-record", "--target", "@DEFAULT_AUDIO_SOURCE@", "--rate", "16000", "--channels", "1", "--format", "s16", "--raw", "-"],
    ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16", "--raw", "-"],
    ["ffmpeg", "-y", "-f", "pulse", "-i", "default", "-ar", "16000", "-ac", "1", "-f", "s16le", "-"],
    ["parecord", "--rate", "16000", "--channels", "1", "--format", "s16le", "--raw"],
    ["arecord", "-r", "16000", "-c", "1", "-f", "S16_LE", "-t", "raw"],
]


def emit(line):
    try:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        os._exit(0)


def die_with_parent():
    # The recorder holds the microphone; it must not outlive this helper.
    try:
        ctypes.CDLL(None).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
    except Exception:
        pass


class Transcriber:
    def __init__(self, ws_connect, key):
        self.ws_connect = ws_connect
        self.key = key
        self.ws = None
        self.recorder = None
        self.committed = []
        self.interim = ""
        self.stopping = asyncio.Event()
        self.ready = asyncio.Event()
        self.final_seen = asyncio.Event()
        self.ended = False
        self.failed = False

    def stop(self):
        self.stopping.set()

    def emit_text(self):
        parts = list(self.committed)
        if self.interim.strip():
            parts.append(self.interim.strip())
        text = " ".join(" ".join(parts).split())
        if text:
            emit("TEXT:" + text)

    def handle(self, raw):
        try:
            data = json.loads(raw)
        except Exception:
            return
        if not isinstance(data, dict):
            return
        if "setupComplete" in data or "setup_complete" in data:
            self.ready.set()
            return
        content = data.get("serverContent") or data.get("server_content")
        if not isinstance(content, dict):
            return
        final = content.get("inputTranscription") or content.get("input_transcription")
        interim = content.get("interimInputTranscription") or content.get("interim_input_transcription")
        if isinstance(final, dict) and final.get("text"):
            segment = final["text"].strip()
            if segment:
                self.committed.append(segment)
                self.interim = ""
                self.emit_text()
                if self.ended:
                    self.final_seen.set()
        elif isinstance(interim, dict) and interim.get("text"):
            self.interim = interim["text"].strip()
            self.emit_text()
        if self.ended and (content.get("turnComplete") or content.get("generationComplete")):
            self.final_seen.set()

    async def receive(self):
        try:
            async for raw in self.ws:
                self.handle(raw)
        except Exception:
            pass

    async def start_recorder(self):
        for argv in RECORDERS:
            if shutil.which(argv[0]) is None:
                continue
            try:
                return await asyncio.create_subprocess_exec(
                    *argv, stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.DEVNULL, preexec_fn=die_with_parent)
            except OSError:
                continue
        return None

    async def stream_audio(self):
        try:
            await asyncio.wait_for(self.ready.wait(), START_FALLBACK)
        except asyncio.TimeoutError:
            pass
        self.recorder = await self.start_recorder()
        if self.recorder is None:
            emit("ERROR:no-recorder")
            self.failed = True
            self.stop()
            return
        try:
            while True:
                chunk = await self.recorder.stdout.readexactly(CHUNK_SIZE)
                await self.ws.send(json.dumps({"realtime_input": {"audio": {
                    "mime_type": "audio/pcm;rate=16000",
                    "data": base64.b64encode(chunk).decode("ascii"),
                }}}))
        except asyncio.IncompleteReadError:
            pass
        except Exception:
            return
        # A recorder that ends by itself ends the dictation like a stop.
        self.stop()

    def stop_recorder(self):
        if self.recorder is not None and self.recorder.returncode is None:
            try:
                self.recorder.terminate()
            except ProcessLookupError:
                pass

    async def run(self):
        try:
            self.ws = await self.ws_connect(ENDPOINT, self.key)
            await self.ws.send(json.dumps(SETUP))
        except Exception:
            emit("ERROR:connect")
            return 1

        receiver = asyncio.ensure_future(self.receive())
        sender = asyncio.ensure_future(self.stream_audio())
        stopper = asyncio.ensure_future(self.stopping.wait())
        await asyncio.wait({receiver, stopper}, return_when=asyncio.FIRST_COMPLETED)
        if receiver.done() and not self.stopping.is_set():
            # The server closed the session while still recording.
            self.stop_recorder()
            sender.cancel()
            emit("ERROR:closed")
            return 1

        self.stop_recorder()
        sender.cancel()
        self.ended = True
        try:
            await self.ws.send(json.dumps({"realtime_input": {"audio_stream_end": True}}))
            await asyncio.wait({receiver, asyncio.ensure_future(self.final_seen.wait())},
                               timeout=FINAL_WAIT, return_when=asyncio.FIRST_COMPLETED)
        except Exception:
            pass
        receiver.cancel()
        try:
            await asyncio.wait_for(self.ws.close(), 0.5)
        except Exception:
            pass
        return 1 if self.failed else 0


async def connect_with(module, url, key):
    headers = {"x-goog-api-key": key}
    try:
        from websockets.asyncio.client import connect
        return await connect(url, additional_headers=headers, max_size=None)
    except ImportError:
        return await module.connect(url, extra_headers=headers, max_size=None)


async def main_async(module, key):
    transcriber = Transcriber(lambda url, k: connect_with(module, url, k), key)
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        loop.add_signal_handler(sig, transcriber.stop)

    def on_stdin():
        try:
            data = os.read(sys.stdin.fileno(), 4096)
        except OSError:
            data = b""
        if not data:
            loop.remove_reader(sys.stdin.fileno())
            transcriber.stop()

    try:
        loop.add_reader(sys.stdin.fileno(), on_stdin)
    except (ValueError, OSError):
        pass
    return await transcriber.run()


def main():
    key = os.environ.get("GEMINI_API_KEY", "")
    if not key:
        emit("ERROR:no-key")
        return 2
    try:
        import websockets
    except ImportError:
        emit("ERROR:no-websockets")
        return 2
    if not any(shutil.which(argv[0]) for argv in RECORDERS):
        emit("ERROR:no-recorder")
        return 1
    return asyncio.run(main_async(websockets, key))


if __name__ == "__main__":
    sys.exit(main())
