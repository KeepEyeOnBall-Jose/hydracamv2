# H8 spike: C4 live preview from a second encoder

Question (court-remote plan, item H8): can a rooted fleet phone publish the C4 preview
(H.264 640x360, 20 fps, 700 kbps, GOP 1 s, no audio) over SRT, with RTMPS as fallback, from a
second MediaCodec encoder on the recorder's Camera2 session, without hurting the recorder?

Status: emulator end to end works. Fleet measurements are pending (see [Fleet results](#fleet-results)).

## Verdict

| | |
|---|---|
| Library | **RootEncoder 2.8.1** (`com.github.pedroSG94.RootEncoder:library`), its SRT and RTMP(S) clients only |
| Transport | SRT works; RTMP and RTMPS work as fallback, with the same encoder output |
| Latency | Emulator: capture → browser arrival p50 ≈ 273 ms (SRT latency 120 ms). Fleet: pending |
| Heat / CPU | Pending |
| Recorder frame drops | Pending |
| Seam | [below](#seam-needed-from-courtcameraservice) |

## Library comparison

| Option | Licence | Size (arm64) | SRT | RTMPS | Notes |
|---|---|---|---|---|---|
| **RootEncoder 2.8.1** | Apache-2.0 | ≈ 0.3 MB, no `.so` | yes, pure Kotlin | yes | Takes our encoder's access units as is. JitPack only. Strips SEI/AUD NALs. `tlsHostVerification` defaults to **false**: production must set it to true |
| StreamPack 3.2.1 + srtdroid | Apache-2.0 + libsrt MPL-2.0 | 7.2 MB `.so` | yes (libsrt) | yes | Owns the camera and encoders. Hard to put on a shared session |
| ffmpeg-kit | LGPL/GPL | large `.so` | yes | yes | Retired upstream |
| libwebrtc (WHIP) | BSD | ≈ 49 MB | n/a | n/a | Own encoder and pacing. Overkill for one-way 360p |
| RootEncoder WHIP | Apache-2.0 | – | – | – | Beta. MediaMTX ingest over SRT is more mature |

## How the spike works

```
Camera2 session (30 fps, one repeating burst)
 ├─ master encoder 1080p 8 Mbps ─▶ master.mp4   (stands in for the recorder)
 ├─ proxy encoder 720p 2 Mbps  ─▶ proxy.mp4     (optional)
 └─ preview: 20 of 30 frames per second
      ├─ direct: 640x360 encoder input surface      (S10e, S20 FE)
      └─ gl: SurfaceTexture 800x450 or 1280x720 → GlScaler → 640x360 encoder  (S7 edge, S9)
           └─ preview encoder (baseline, CBR, GOP 1 s) ─▶ RootEncoder SrtClient / RtmpClient ─▶ MediaMTX
```

- **20 fps from a 30 fps camera.** The preview surface is only in 2 of every 3 requests of the
  repeating burst (`SharedCameraSession`). There is no frame dropping in code, and the master
  still gets every frame.
- **PTS = sensor timestamp** on every track. The GL path keeps it via
  `eglPresentationTimeANDROID(texture.timestamp)`.
- **Latency tag.** Each preview access unit carries its capture wall-clock time in a filler NAL
  (type 12). That is the only NAL type that survives RootEncoder → MediaMTX → WebRTC. The
  viewer reads it with `RTCRtpScriptTransform`, matches it to the frame shown with
  `requestVideoFrameCallback`, and corrects for the clock offset of both ends (SNTP).
- **Camera sizes.** Camera2 rejects a MediaCodec surface whose size is not in the camera's PRIV
  list:

  | Phone | SDK | 640x360 to MediaCodec | Path |
  |---|---|---|---|
  | S7 edge | 26 | no (800x450, 1280x720) | gl |
  | S9 | 29 | no (800x450, 960x540) | gl |
  | S10e | 31 | yes | direct |
  | S20 FE (G780G) | 33 | yes | direct |

## Contract findings (C1/C4)

1. **SRT token.** The token must go in the streamid password slot:
   `srt://relay:8890?streamid=publish:court/<id>/<slot>:device:<jwt>`. With the C4 `&token=<jwt>`
   form, MediaMTX never passes the token on. With the password-slot form, MediaMTX sends it to the
   webhook in `token`.
2. **RTMP(S) token.** Use `rtmps://relay:1936/court/<id>/<slot>?token=<jwt>`. RTMPS on 443
   collides with Caddy on the relay host. Use a separate port, or terminate TLS in Caddy with a
   TCP proxy.
3. **MediaMTX keys.** Use `authMethod: http` + `authHTTPAddress`. The contract's
   `externalAuthenticationURL` is the old name. Add `authHTTPExclude` for `api` and `metrics`, or
   the control API also hits the webhook.
4. **Stop is cloud-driven.** MediaMTX does not tell the phone that the last viewer left. Without
   `preview.stop` (or a TTL), the phone keeps publishing.
5. **640x360 is not a camera size on S7 edge and S9.** It stays the stream size; those phones
   scale in GL.

## Seam needed from CourtCameraService

`CourtCameraService` keeps the camera, the session and the recorder. The preview needs only this:

```kotlin
interface PreviewTargetHost {
    /** Supported sizes for a MediaCodec / SurfaceTexture target on the recording camera. */
    fun outputSizes(consumer: Class<*>): List<Size>

    /**
     * Adds [surface] to the capture session and includes it in [fps] of every camera-fps frames
     * (repeating burst). Reconfigures the session once. The recorder's surfaces keep every frame.
     */
    fun addPreviewTarget(surface: Surface, fps: Int)

    /** Removes the target (one more reconfigure). Idempotent. */
    fun removePreviewTarget()

    /** Offset from SENSOR_TIMESTAMP to wall-clock ms, for the latency tag. */
    fun sensorToWallMs(): Long
}
```

- Session reconfiguration on add and remove may cost the recorder a gap of a few frames.
  **To measure (fleet):** if the gap matters, keep the preview target in the session for the
  whole court session and only turn the encoder on and off.
- `preview.start` / `preview.stop` (C1) map to `addPreviewTarget` / `removePreviewTarget` plus
  publisher start/stop. The GL scaler and publisher stay inside the preview module.

## Fleet results

Pending. Scenarios per phone, 20 min each, cooled to ≤ 30 °C battery before each:

- `base`: master 1080p + proxy 720p
- `preview`: base + C4 preview over SRT

```
python3 scripts/fleet_run.py --serial <adb serial> --label <phone> --scenario base
python3 scripts/fleet_run.py --serial <adb serial> --label <phone> --scenario preview --url '<srt url>'
python3 scripts/summarize.py results
```

## Run it

Relay (MediaMTX v1.21.3 + dummy auth/viewer server):

```
MEDIAMTX=/path/to/mediamtx HOST=0.0.0.0 ./scripts/relay-local.sh
curl 'http://127.0.0.1:8780/mint?typ=publish&path=court/demo/left'   # publish JWT
curl 'http://127.0.0.1:8780/mint?typ=whep&path=court/demo/left'      # viewer JWT
open 'http://127.0.0.1:8780/?whep=http://127.0.0.1:8889/court/demo/left/whep&token=<whep jwt>'
```

Phone (spike app `com.amaia23.hydracam.spike.preview`, separate from HydraCam):

```
cd android && ./gradlew assembleRelease
adb install -r app/build/outputs/apk/release/app-release.apk
adb shell am start -n com.amaia23.hydracam.spike.preview/.SpikeActivity \
  --es url 'srt://<relay>:8890?streamid=publish:court/demo/left:device:<jwt>' --ei duration 60
```

Extras: `master 1080p|720p`, `proxy`, `record`, `keep` (keep mp4s), `preview`, `previewPath auto|direct|gl`,
`glSource WxH`, `srtLatency`, `insecureTls` (self-signed RTMPS only), `ntp host|none`,
`timeNal filler|sei|none`, `duration` (s), `stop`. Output:
`/sdcard/Android/data/com.amaia23.hydracam.spike.preview/files/h8/<run>/` (`stats.jsonl` every 5 s,
`summary.json`).

Emulator notes: the emulator HAL rejects a direct 640x360 encoder. Its software encoder also reads
back GL frames as garbage. So GL pixel output needs a real phone (S7 edge). Emulator latency numbers
need `ntp` on, because the emulator clock is ≈ 300 ms off.
