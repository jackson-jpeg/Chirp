#!/usr/bin/env python3
"""[VPS] Encode 16 kHz mono PCM WAVs into ChirpChirps' Opus voice-message format.

    python3 scripts/demo-audio/encode_opus_frames.py <in.wav>... --out <dir>

The app's format (VoiceMessageQueue.queueMessage / decodeFrames) is
    [frameCount: UInt32 BE] then per frame [length: UInt32 BE][Opus packet]
where every packet is 20 ms of 16 kHz mono audio (320 samples), encoded the
way OpusCodec encodes live push-to-talk: OPUS_APPLICATION_VOIP at 24 kbps.
Decoding goes through the same AudioEngine.receiveAudioPacket path as live
audio, so a clip that decodes here decodes in the app.

Each output is verified by decoding every frame back with libopus; any frame
that fails to decode aborts the run.
"""
import argparse, ctypes, ctypes.util, struct, sys, wave
from pathlib import Path

RATE, CH, FRAME, BITRATE = 16000, 1, 320, 24000
OPUS_APPLICATION_VOIP = 2048
OPUS_SET_BITRATE_REQUEST = 4002

lib = ctypes.CDLL(ctypes.util.find_library('opus') or 'libopus.so.0')
lib.opus_encoder_create.restype = ctypes.c_void_p
lib.opus_encoder_create.argtypes = [ctypes.c_int32, ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
lib.opus_encode.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int16), ctypes.c_int, ctypes.c_char_p, ctypes.c_int32]
lib.opus_decoder_create.restype = ctypes.c_void_p
lib.opus_decoder_create.argtypes = [ctypes.c_int32, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
lib.opus_decode.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int32, ctypes.POINTER(ctypes.c_int16), ctypes.c_int, ctypes.c_int]
lib.opus_encoder_ctl.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int32]

def encode(path: Path) -> tuple[bytes, int]:
    with wave.open(str(path)) as w:
        assert w.getframerate() == RATE and w.getnchannels() == CH and w.getsampwidth() == 2, \
            f"{path}: need 16 kHz mono 16-bit, got {w.getframerate()} Hz {w.getnchannels()}ch {8*w.getsampwidth()}-bit"
        pcm = w.readframes(w.getnframes())
    samples = list(struct.unpack(f'<{len(pcm)//2}h', pcm))
    samples += [0] * (-len(samples) % FRAME)          # pad the tail to a whole frame

    err = ctypes.c_int()
    enc = lib.opus_encoder_create(RATE, CH, OPUS_APPLICATION_VOIP, ctypes.byref(err))
    assert err.value == 0, f"encoder create failed: {err.value}"
    lib.opus_encoder_ctl(enc, OPUS_SET_BITRATE_REQUEST, BITRATE)
    dec = lib.opus_decoder_create(RATE, CH, ctypes.byref(err))
    assert err.value == 0, f"decoder create failed: {err.value}"

    frames, outbuf = [], ctypes.create_string_buffer(1500)
    pcm_out = (ctypes.c_int16 * FRAME)()
    for i in range(0, len(samples), FRAME):
        chunk = (ctypes.c_int16 * FRAME)(*samples[i:i + FRAME])
        n = lib.opus_encode(enc, chunk, FRAME, outbuf, len(outbuf))
        assert n > 0, f"{path}: opus_encode failed at frame {i // FRAME}: {n}"
        packet = outbuf.raw[:n]
        decoded = lib.opus_decode(dec, packet, n, pcm_out, FRAME, 0)
        assert decoded == FRAME, f"{path}: frame {i // FRAME} decoded to {decoded} samples"
        frames.append(packet)

    body = struct.pack('>I', len(frames)) + b''.join(struct.pack('>I', len(f)) + f for f in frames)
    return body, len(frames)

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('wavs', nargs='+', type=Path)
    ap.add_argument('--out', type=Path, required=True)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    for wav in a.wavs:
        body, count = encode(wav)
        dest = a.out / f"{wav.stem}.opusframes"
        dest.write_bytes(body)
        print(f"{dest.name}: {count} frames = {count * 20 / 1000:.2f}s, {len(body)} bytes")

if __name__ == '__main__':
    main()
