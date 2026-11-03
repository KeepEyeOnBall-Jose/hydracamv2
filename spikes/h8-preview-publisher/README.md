# H8 spike: C4 live preview from a second encoder

Question (court-remote plan, item H8): can a rooted fleet phone publish the C4 preview
(H.264 640x360, 20 fps, 700 kbps, GOP 1 s, no audio) over SRT, with RTMPS as fallback, from a
second MediaCodec encoder on the recorder's Camera2 session, without hurting the recorder?

Status: **yes**. Measured on S10e, S20 FE and S7 edge on 2026-11-03 (20 min per scenario, phones
plugged in, local MediaMTX relay on the club LAN, headless Chrome WHEP viewers). S9 not tested
(same GL path as S7 edge).

## Verdict

| | |
|---|---|
| Library | **RootEncoder 2.8.1** (`com.github.pedroSG94.RootEncoder:library`), its SRT and RTMP(S) clients only |
| Transport | SRT: 1 connect, 0 failures, 0 dropped frames per phone in 20 min. RTMP/RTMPS fallback works with the same encoder output (emulator) |
| Latency | Glass to glass p50 **287 / 298 / 298 ms**, p95 304 / 313 / 313 ms (S10e / S20 FE / S7 edge). 0–1 viewer-dropped frames, 0 packets lost |
| Heat / CPU | Preview adds 0–4 points of device CPU and 1–4 points of app CPU. Hottest zone +2 to +5 °C. Battery ≤ 36.1 °C after 20 min. Only the S20 FE reached thermal status 1 ("light"), at 11.6 min |
| Recorder frame drops | **S10e, S7 edge: none** (same as without preview). **S20 FE: 0.5 % of master frames** (188 one-frame gaps in 20 min vs 22 without; max gap 67 ms). See [S20 FE drops](#s20-fe-drops) |
| Bitrate | The C4 700 kbps target is not met on two phones: preview 961 / 839 / 699 kbps. A 530 kbps target still gives 916 / 824. Proxy 2000 kbps target gives 2455 / 2485 / 1996 |
| Seam | Preview surface stays in the session for the camera's whole life; on/off only changes the repeating burst. Camera opens for live view before recording. [Details](#seam-needed-from-courtcameraservice) |

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

The base scenario (1080p 8 Mbps + 720p 2 Mbps, 30 fps) matches the court recorder's
`RecordProfile`.

- **20 fps from a 30 fps camera.** The preview surface is only in 2 of every 3 requests of the
  repeating burst (`SharedCameraSession`). There is no frame dropping in code, and the master
  still gets every frame.
- **PTS clock differs by path.** GL path: encoder PTS are sensor timestamps
  (`eglPresentationTimeANDROID(texture.timestamp)`). Direct path (S10e, S20 FE): the camera
  service gives video-encoder streams `CLOCK_MONOTONIC` timestamps, while `SENSOR_TIMESTAMP` is
  BOOTTIME. PTS lag the sensor clock by the phone's total deep-sleep time (2.6 h on the S10e and
  9.3 h on the S20 FE in these runs). The spike finds the exact offset from the first matching
  frame (`ptsClock`, `ptsToSensorMs` in `summary.json`). The recorder's master and proxy encoders
  get the same `MONOTONIC` PTS on those phones.
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

## Fleet results

Per phone, 20 min each: `base` (master + proxy) and `preview` (base + C4 preview over SRT).
3-min variants: `toggle-burst` / `toggle-session` (preview on/off every 10 s, see
[seam](#seam-needed-from-courtcameraservice)), `kbps530` (preview target 530 kbps), `srt60`
(phone SRT latency 60 ms), and S20 FE diagnostics `gl` and `fps30`. Raw data: `results/`
(`summary.json`, `stats.jsonl` every 5 s from the app, `host.jsonl` every 5 s from adb,
`viewer.jsonl` from the browsers).

Reading the tables:

- **CPU** is the `/proc/stat` delta over the run. Device % is all cores; app % is the spike app's
  share of the whole device.
- **Temperatures.** The preview runs started warmer (≈ 30 °C battery vs ≈ 24 °C), so end
  temperatures are not a clean comparison. In the last 5 min the preview runs rose only
  +0.4 / +0.5 °C (S10e / S20 FE) vs +0.7 / +0.8 °C for base, so they were levelling off.
- **Gaps.** A PTS gap is a step > 1.5 frame intervals in the master track. A 67 ms gap is one
  missing frame. The S7 base run's 574 ms gap is at stop (shutdown artifact).
- **Toggle runs.** Preview frames are ≈ half of expected because the preview is off half the
  time.

<!-- summarize.py output below -->
### samsung SM-G970F API 31

| run | preview path | min | preview on/off | master frames/expected | master PTS gaps | master max gap ms | cam buffer lost | device CPU % | app CPU % of device | battery °C start | end | max | hottest zone °C | thermal status max | preview fps p50 | preview frames/expected | publisher dropped | arrival ms p50 | g2g ms p50 | viewer dropped |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| s10e-base-20261103-042915 | – | 20.2 | – | 36219/36294 | 2 | 67 | 0 | 20 | 3.0 | 24.3 | 31.5 | 31.5 | 51 | 0 | – | – | – | – | – | 0 |
| s10e-preview-20261103-045036 | direct | 20.2 | – | 36218/36293 | 1 | 67 | 0 | 24 | 4.7 | 29.9 | 34.1 | 34.1 | 53 | 0 | 20 | 24145/24194 | 0 | 261 | 287 | 0 |
| s10e-preview-kbps530-20261103-051918 | direct | 3.2 | – | 5693/5693 | 1 | 67 | 0 | 24 | 4.7 | 32.2 | 33.2 | 33.2 | 52 | 0 | 20 | 3795/3794 | 0 | 264 | 275 | 0 |
| s10e-preview-srt60-20261103-052314 | direct | 3.2 | – | 5688/5689 | 2 | 67 | 0 | 25 | 4.6 | 32.3 | 33.2 | 33.2 | 54 | 0 | 20 | 3792/3792 | 0 | 264 | 275 | 0 |
| s10e-preview-toggle-burst-20261103-051147 | direct | 3.2 | burst x18, 6 ms avg | 5693/5692 | 0 | 33 | 0 | 22 | 3.9 | 32.6 | 33.2 | 33.2 | 52 | 0 | 18.4 | 1992/3794 | 0 | 268 | 281 | 0 |
| s10e-preview-toggle-session-20261103-051532 | direct | 3.2 | session x18, 490 ms avg | 5456/5690 | 19 | 519 | 0 | 22 | 3.8 | 32.5 | 33.1 | 33.1 | 51 | 0 | 8.8 | 1832/3792 | 0 | 269 | 282 | 0 |

### samsung SM-G780G API 33

| run | preview path | min | preview on/off | master frames/expected | master PTS gaps | master max gap ms | cam buffer lost | device CPU % | app CPU % of device | battery °C start | end | max | hottest zone °C | thermal status max | preview fps p50 | preview frames/expected | publisher dropped | arrival ms p50 | g2g ms p50 | viewer dropped |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| s20fe-base-20261103-042915 | – | 20.2 | – | 36276/36294 | 22 | 67 | 0 | 27 | 2.6 | 23.8 | 30.5 | 30.5 | 46 | 0 | – | – | – | – | – | 0 |
| s20fe-preview-20261103-045035 | direct | 20.2 | – | 36111/36295 | 188 | 67 | 0 | 27 | 3.6 | 29.8 | 34.6 | 34.6 | 51 | 1 | 20 | 24072/24194 | 0 | 276 | 298 | 1 |
| s20fe-preview-fps30-20261103-053221 | direct | 3.2 | – | 5671/5691 | 21 | 67 | 0 | 29 | 3.9 | 32.6 | 33.7 | 33.7 | 49 | 1 | 30 | 5669/5689 | 0 | 268 | 293 | 0 |
| s20fe-preview-gl-20261103-052757 | gl | 3.2 | – | 5677/5693 | 17 | 67 | 0 | 28 | 4.0 | 32.9 | 33.7 | 33.7 | 48 | 0 | 20 | 3784/3795 | 0 | 305 | 316 | 0 |
| s20fe-preview-kbps530-20261103-051958 | direct | 3.2 | – | 5670/5692 | 23 | 67 | 0 | 27 | 3.6 | 32.7 | 33.5 | 33.5 | 48 | 0 | 20 | 3779/3794 | 0 | 271 | 284 | 0 |
| s20fe-preview-srt60-20261103-052356 | direct | 3.2 | – | 5666/5694 | 29 | 67 | 0 | 28 | 3.6 | 32.9 | 33.7 | 33.7 | 52 | 0 | 20 | 3776/3795 | 0 | 294 | 307 | 0 |
| s20fe-preview-toggle-burst-20261103-051250 | direct | 3.2 | burst x18, 5 ms avg | 5674/5693 | 20 | 67 | 0 | 27 | 3.3 | 32.6 | 33.0 | 33.0 | 46 | 0 | 18.4 | 1984/3794 | 0 | 275 | 291 | 0 |
| s20fe-preview-toggle-session-20261103-051609 | direct | 3.2 | session x18, 400 ms avg | 5480/5695 | 30 | 451 | 0 | 27 | 3.1 | 33.0 | 33.3 | 33.3 | 49 | 0 | 9.8 | 1847/3795 | 0 | 278 | 298 | 0 |

### samsung SM-G935F API 26

| run | preview path | min | preview on/off | master frames/expected | master PTS gaps | master max gap ms | cam buffer lost | device CPU % | app CPU % of device | battery °C start | end | max | hottest zone °C | thermal status max | preview fps p50 | preview frames/expected | publisher dropped | arrival ms p50 | g2g ms p50 | viewer dropped |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| s7-base-20261103-042915 | – | 20.2 | – | 36305/36310 | 1 | 574 | 0 | 24 | 5.3 | 26.2 | 33.3 | 33.3 | 66 | – | – | – | – | – | – | 0 |
| s7-preview-20261103-045741 | gl | 20.2 | – | 36304/36294 | 1 | 67 | 0 | 28 | 9.2 | 30.0 | 36.0 | 36.1 | 70 | – | 20 | 24203/24196 | 0 | 274 | 298 | 0 |
| s7-preview-srt60-20261103-053306 | gl | 3.2 | – | 5696/5693 | 0 | 37 | 0 | 28 | 9.2 | 33.0 | 33.9 | 33.9 | 65 | – | 20 | 3797/3795 | 0 | 270 | 301 | 0 |
| s7-preview-toggle-burst-20261103-052335 | gl | 3.2 | burst x18, 10 ms avg | 5694/5691 | 0 | 35 | 0 | 26 | 7.8 | 33.0 | 33.7 | 33.7 | 64 | – | 18.2 | 2003/3794 | 0 | 269 | 290 | 0 |
| s7-preview-toggle-session-20261103-052851 | gl | 3.2 | session x18, 531 ms avg | 5292/5697 | 18 | 841 | 0 | 25 | 6.8 | 33.0 | 33.4 | 33.4 | 63 | – | 9.6 | 1770/3798 | 0 | 265 | 282 | 0 |

### Latency breakdown (20-min runs)

| | S10e | S20 FE | S7 edge |
|---|---|---|---|
| Camera delivery (sensor → app) | 56 ms | 39 ms | 71 ms |
| Capture → encoded, p50 / p95 | 98 / 113 ms | 116 / 121 ms | 111 / 122 ms |
| Capture → browser arrival, p50 | 261 ms | 276 ms | 274 ms |
| Glass to glass, p50 / p95 | 287 / 304 ms | 298 / 313 ms | 298 / 313 ms |
| WebRTC jitter buffer / decode | 14 / 2 ms | 16 / 2 ms | 15 / 2 ms |

SRT latency (120 ms) is the biggest single part. Setting 60 ms on the phone changes nothing
(S10e 275 vs 275 ms in the same hour, S7 edge 301 vs 298 ms): SRT uses the larger of both ends' values, and MediaMTX stays at its
default of 120 ms. To go lower, set it on the relay too. Not needed for C4.

### Bitrate

| kbps (target) | S10e | S20 FE | S7 edge |
|---|---|---|---|
| Preview video (700) | 961 | 839 | 699 |
| Preview video (530) | 916 | 824 | – |
| Preview on the wire, SRT/TS (700) | 1026 | 898 | 753 |
| Proxy video (2000) | 2455 | 2485 | 1996 |
| Master video (8000) | 7893 | 7990 | 7987 |

The S10e and S20 FE encoders overshoot low targets in CBR mode. Lowering the target barely
helps, so the encoder has a floor near 820–920 kbps at 640x360/20. The wire adds ≈ 7 % (MPEG-TS
and SRT). The same overshoot hits the court recorder's proxy encoder. Per camera during
recording plus live view this is ≈ 2.5 Mbps proxy + ≈ 1 Mbps preview, above the K2
`upload.policy maxKbps` of 2500. Budget against measured rates, not targets.

### S20 FE drops

S20 FE base already loses ≈ 1 master frame per minute; with the preview it is ≈ 9 per minute,
evenly over the 20 min (not thermal). S10e and S7 edge lose none with the same code.

Where the drops come from (3-min runs, master gaps per minute):

| S20 FE run | Preview frames | Gaps / min |
|---|---|---|
| base (no preview) | – | 1.1 |
| preview, direct, 20 of 30 frames (20 min) | 20 fps | 9.3 |
| preview, GL path (SurfaceTexture consumer) | 20 fps | 5.3 |
| preview, direct, every frame (`setRepeatingRequest`) | 30 fps | 6.6 |
| toggle-burst, 5-s windows with preview on | 20 fps | 12 |
| toggle-burst, 5-s windows with preview off (surface still configured) | 0 | 1.3 |

So the drops come from the camera producing preview frames at all, whatever the consumer
(encoder or GL) and cadence. Having the surface configured costs nothing. It looks like a camera
HAL limit with three streams on this phone (SM-G780G), not something the preview code can fix.
It costs one 67 ms master gap every 5–12 s, and only while someone watches.

Options, untested: feed proxy and preview from one camera stream through GL (two encoders on one
SurfaceTexture, so the camera keeps two streams), or accept it on this model.

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
6. **Idle publishers are dropped.** If the phone stops sending frames but keeps the SRT
   connection, MediaMTX closes it after 10 s (`readTimeout`, "Shutdown received from server").
   `preview.stop` must disconnect, and `preview.start` must reconnect.
7. **700 kbps is a target, not a cap.** See [Bitrate](#bitrate).

## Seam needed from CourtCameraService

What the measurements say about the seam:

1. **Never rebuild the capture session to turn the preview on or off.** Toggling by rebuilding
   the session costs the recorder 400–530 ms per switch (master max gap 451–841 ms, 4–7 % of
   master frames lost in the toggle runs). Toggling by changing only the repeating burst takes
   5–10 ms and costs nothing (0 master gaps on S10e and S7 edge). So the preview surface must be
   in every capture session from camera open to close.
2. **Live view comes before recording.** The visitor sees the stream before signing in. The
   camera must open and stream with no recording running.
3. **A dedicated preview encoder, not the recorder's proxy output.** Reusing the proxy encoder
   (720p, 2 Mbps, GOP 2 s, only while recording) does not give the C4 stream, gives no live view
   before recording, and would publish ≈ 2.5 Mbps twice during recording. The dedicated encoder
   costs ≤ 4 points of CPU and nothing on the recorder (S10e, S7 edge).
4. **Sizes come from the camera.** On S7 edge and S9 the preview module needs a SurfaceTexture
   size (800x450) and scales in GL.
5. **Clocks.** On the direct path, encoder PTS (all encoders, also the recorder's) are
   `CLOCK_MONOTONIC`, while `CaptureResult.SENSOR_TIMESTAMP` is BOOTTIME. A PTS clock that picks
   the closer clock on the first frame works for wall-clock mapping. On API 33+,
   `OutputConfiguration.setTimestampBase(TIMESTAMP_BASE_SENSOR)` should align them (untested).

Proposed API (the camera owner implements it; the preview module stays outside):

```kotlin
interface PreviewTargetHost {
    /** Sizes the court camera can output to a MediaCodec / SurfaceTexture target. */
    fun previewOutputSizes(consumer: Class<*>): List<Size>

    /**
     * The preview surface, included in every capture session from camera open to close.
     * Set it before the camera opens: setting it on an open camera rebuilds the session once
     * (≈ 0.5 s recorder gap). null removes it.
     */
    fun setPreviewSurface(surface: Surface?)

    /**
     * Frames per second sent to the preview surface, 0 = off. Changes only the repeating burst
     * (fps of every camera-fps requests), never the session. Recorder surfaces keep every frame.
     */
    fun setPreviewFps(fps: Int)

    /** Keep the camera open and streaming with no recording (live view before sign-in). */
    fun holdCameraForPreview(hold: Boolean)

    /** Wall-clock ms for a capture, for the latency tag and viewer timing. */
    fun captureWallMs(sensorTimestampNs: Long): Long
}
```

- `preview.start` (C1): connect the publisher, request a sync frame, `setPreviewFps(20)`.
  `preview.stop`: `setPreviewFps(0)`, disconnect. The encoder, GL scaler and publisher stay in the
  preview module.
- The spike keeps the preview encoder running while off (no input means no output and no
  measurable cost). `MediaCodec.createPersistentInputSurface()` would let the codec be released
  without changing the camera's surface (untested).
- This replaces the recorder's current low-encoder listener (proxy reuse) for live view. That
  listener can stay for other uses.

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
`glSource WxH`, `previewKbps`, `previewFps`, `srtLatency`, `insecureTls` (self-signed RTMPS only),
`ntp host|none`, `timeNal filler|sei|none`, `toggle burst|session` + `toggleS` (preview on/off
test), `duration` (s), `stop`. Output:
`/sdcard/Android/data/com.amaia23.hydracam.spike.preview/files/h8/<run>/` (`stats.jsonl` every 5 s,
`summary.json`).

Fleet runs (host-side sampling, cools the phone first, pulls results):

```
python3 scripts/fleet_run.py --serial <adb serial> --label <phone> --scenario base
python3 scripts/fleet_run.py --serial <adb serial> --label <phone> --scenario preview --url '<srt url>'
python3 scripts/fleet_run.py ... --scenario preview --url '<srt url>' --minutes 3 \
  --tag toggle-burst --extra '--es toggle burst --ei toggleS 10'
python3 scripts/summarize.py results --viewer results/viewer.jsonl
```

Emulator notes: the emulator HAL rejects a direct 640x360 encoder. Its software encoder also reads
back GL frames as garbage. So GL pixel output needs a real phone (S7 edge). Emulator latency numbers
need `ntp` on, because the emulator clock is ≈ 300 ms off.
