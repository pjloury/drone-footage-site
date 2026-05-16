# drone-footage-site — project notes

Static one-page videography portfolio. Single `index.html`, deployed on Vercel
at `drones.pjloury.com`. Video files live in **Cloudflare R2** bucket
`drone-footage` and are served direct to the browser via the public R2 URL
`https://pub-abee44b9f56049338f38452f0835b88f.r2.dev` (no Vercel rewrite).
The `--backfill-cache` mode of `encode_and_upload.sh` stamps every R2 object
with `Cache-Control: public, max-age=31536000, immutable` so repeat visits
serve from browser disk cache.

## Architecture quick map

- `index.html` — entire app. `BASE_URL` constant near top points at the R2
  pub URL. The `VIDEOS` array is the playlist; commented-out entries are
  permanently excluded. `setVideoSrc()` is the single chokepoint that sets
  both `video.src` and `video.poster` — route any new src writes through it.
- `encode_and_upload.sh` — three-step pipeline per clip: H.264 1080p@3Mbps
  mobile (faststart, fixed 2s keyframes), faststart-muxed desktop, 720p
  poster JPG. Uploads all three to R2 with the long cache header. Flags:
    - `--force-mobile` — re-encode mobile even if already in R2 (use after
      changing the encode settings)
    - `--backfill-cache` — metadata-only update of existing R2 objects, no
      encoding
    - `--skip-desktop-upload` — skip re-uploading the desktop re-mux
- `vercel.json` — only serves the static shell. No video proxying.

## Outstanding TODOs

### 🛠 Restore video-09 ("Above SoMa")
**Status:** Currently commented out of the `VIDEOS` array in `index.html`
(see the `// TODO: source corrupt` line, ~line 435).

**What's broken:**
- Local source `/Users/Shared/Aerial Local/Above Soma.mov` is corrupt —
  ffmpeg reports "Invalid data found when processing input."
- R2 still has `video-09.mp4` (209 MB) but its moov atom is unreadable —
  the file is QuickTime/ProRes (`ftyp qt  `) renamed `.mp4`. ffmpeg can't
  decode it; browser may or may not.
- `video-09-mobile.mp4` and `video-09-poster.jpg` do not exist in R2.

**Likely cause:** the `--backfill-cache` multipart copy-in-place corrupted
the byte layout for this particular large file. Other large desktop files
were re-uploaded fresh by the subsequent `--force-mobile` run, so they're
fine.

**To fix:**
1. Locate an intact source for "Above Soma" (Dropbox, iCloud, Time Machine,
   original SD card, etc.).
2. Drop it as `/Users/Shared/Aerial Local/Above Soma.mov`.
3. Run a one-shot encode for just this clip (or temporarily edit
   `encode_and_upload.sh`'s NUMS/FILES arrays to only contain `09`).
4. Once the new mobile + poster + desktop are in R2, uncomment the
   `video-09` line in `index.html`'s `VIDEOS` array.
5. Commit + push.

### 🛠 Latent: re-encode high-bitrate desktop clips (deferred)
**Status:** Not currently exhibiting issues. Documented here in case
desktop playback starts lurching again.

**What was observed (2026-04-26):** After the Vercel `/videos/*` rewrite
was removed and desktop bytes started flowing direct from R2's pub URL,
some desktop clips lurched (~half-second of playback then a pause loop).
Pre-removal, Vercel's edge cache was smoothing this out; the R2 pub URL
doesn't get the same aggressive Cloudflare edge caching (no
`cf-cache-status` header is returned, consistent with Cloudflare's
"intended for development" warning on `pub-*.r2.dev` URLs).

User reported lurching on Villa Collina (18) and Fort Funston (36);
smooth on Telegraph Hill (7), USF (21), SF Embarcadero (60), Park City
(27/41).

**Diagnosis:** Two distinct causes overlap.
1. **High file bitrate** — 8 desktop clips have average bitrates
   ≥40 Mbps (one as high as 130 Mbps). Even on home wifi, peak
   instantaneous demand during motion-heavy scenes outpaces
   throughput → underbuffer → lurch.
2. **CDN variability** — some 20-Mbps clips (e.g. video-36) also
   lurch, even though they shouldn't on bitrate alone. This is
   Cloudflare's R2 pub URL not aggressively edge-caching less-popular
   files. Re-encoding won't help these — only Option B (custom domain
   on R2 + Cache Rules) or accepting cold-cache hits will.

**The 8 Tier-1 candidates (>40 Mbps avg) — re-encode these first if
issues return:**

| video | caption                          | dur  | size  | avg Mbps |
| ----- | -------------------------------- | ---- | ----- | -------- |
| 30    | Vogelsang Lake, Yosemite         | 27s  | 422MB | **130**  |
| 18    | Villa Collina                    | 7s   | 74MB  | **90**   |
| 19    | Waves                            | 12s  | 125MB | **90**   |
| 37    | Fort Funston & Golden Gate       | 14s  | 148MB | **90**   |
| 50    | Palma, Mallorca                  | 7s   | 41MB  | 52       |
| 62    | Sather Tower, Berkeley           | 41s  | 250MB | 51       |
| 22    | Old Valencia, Spain              | 69s  | 416MB | 50       |
| 32    | Almaden Green                    | 89s  | 534MB | 50       |

**Tier-2 candidates (30–40 Mbps, all 60-fps clips that should
probably also drop):** 06, 14, 16, 23, 26, 29, 35, 42, 45, 46, 47, 51.

**Plan when triggered:**
1. Pick a target bitrate. Defaults discussed:
   - **15 Mbps** (YouTube-grade) — small files, ~95% confident lurching
     stops; minor quality drop only visible on a 4K monitor at full screen
   - **25 Mbps** (gallery-grade) — slightly bigger files, near-original
     quality, still solves all observed peaks
2. For each Tier-1 number, run from local source (sources are in
   `/Users/Shared/Aerial Local/...` — see `encode_and_upload.sh`
   FILES array for the exact filename per number):

   ```bash
   ffmpeg -i "$SRC" \
     -c:v libx265 -tag:v hvc1 -preset medium \
     -b:v 15M -maxrate 20M -bufsize 30M \
     -c:a aac -b:a 128k \
     -movflags +faststart \
     -y "$DESKTOP_OUT"
   ```

   `-tag:v hvc1` is required so Apple/Safari recognize the HEVC
   stream. Use `videotoolbox` instead of `libx265` for faster
   hardware encode on M-series Macs:
   `-c:v hevc_videotoolbox -b:v 15M -tag:v hvc1`.

3. Upload with the standard cache header:
   ```bash
   aws s3 cp "$DESKTOP_OUT" "s3://drone-footage/video-${N}.mp4" \
     --profile r2 \
     --endpoint-url "https://73fc4c58d8b8e9d05a8410bde37ff80d.r2.cloudflarestorage.com" \
     --content-type "video/mp4" \
     --cache-control "public, max-age=31536000, immutable"
   ```
4. **Cache-bust** for desktop URLs. Add a `DESKTOP_VERSION` constant
   in `index.html` (mirroring the existing `MOBILE_VERSION`) and
   append `?v=${DESKTOP_VERSION}` to non-mobile URLs in `url(i)`. Bump
   it whenever desktop bitrate changes so browsers re-fetch.

**Probe to re-confirm before acting (some files may have been
replaced since this was written):**
```bash
for n in 18 19 22 30 32 37 50 62; do
  size=$(curl -sI "https://pub-abee44b9f56049338f38452f0835b88f.r2.dev/video-${n}.mp4" \
    | awk -F': ' '/[Cc]ontent-[Ll]ength/ {print $2}' | tr -d '\r')
  curl -sSL -r 0-262143 -o /tmp/probe.mp4 \
    "https://pub-abee44b9f56049338f38452f0835b88f.r2.dev/video-${n}.mp4" 2>/dev/null
  dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 /tmp/probe.mp4)
  python3 -c "print(f'video-${n}: {round($size*8/$dur/1e6,1)} Mbps')"
done
```

## Encoding gotchas

### Long-GOP decoder stalls on mobile (fixed 2026-05-16)

**Symptom:** Video completely freezes mid-playback on mobile. The blue GPS
dot keeps pulsing (CSS animations are compositor-thread, unaffected) but
`currentTime` stops advancing. The browser never fires `waiting` because
the network buffer is full — the GPU decoder itself is stuck. The existing
8s auto-skip (which is armed by `waiting`) therefore never triggers.

**Root cause:** x264's default keyframe placement uses scene-detection. Slow
drone pans have almost no scene changes, so x264 can go 8–15+ seconds
between keyframes. With a long GOP the hardware decoder must maintain
reference-frame state for the entire interval. Under memory or thermal
pressure this can cause the decoder to stall mid-GOP, and recovery requires
waiting for the next keyframe — up to 8 seconds away.

**Diagnosed by probing keyframe spacing:**
```bash
curl -sSL -r 0-4194303 -o /tmp/probe.mp4 \
  "https://pub-abee44b9f56049338f38452f0835b88f.r2.dev/video-49-mobile.mp4"
ffprobe -v error -select_streams v:0 \
  -show_entries packet=pts_time,flags \
  -of csv=p=0 /tmp/probe.mp4 | awk -F',' '$2~/K/ {print "keyframe at " $1 "s"}'
# Before fix: keyframe at 0s, next at 8.34s
# After fix:  keyframe at 0s, 2s, 4s, 6s, 8s, 10s ...
```

**Fix (already in `encode_and_upload.sh`):**
```
-g 60 -keyint_min 60   # force keyframe every 60 frames = every 2s at 30fps
-bf 2                  # cap B-frames at 2, reduces decoder memory pressure
```
This was applied to the entire catalog on 2026-05-16 via
`bash encode_and_upload.sh --force-mobile --skip-desktop-upload`.

**When to re-run:** Any time new clips are added, the script already
includes these flags — just run normally. If a specific clip is suspected
of stalling, probe its keyframe spacing with the snippet above before
re-encoding.

**Playback-side defense:** `index.html` also has a `setInterval` watchdog
(every 2s) that detects `currentTime` not advancing on an active video,
emits `video_stall_watchdog` to PostHog, and arms the mobile auto-skip
timer. This catches stalls that slip through even with 2s keyframes (thermal
throttle, etc.). Look for `video_stall_watchdog` events in PostHog if
freezes recur.

### 60 fps source clips need `fps=30` on the mobile encode
About 22% of the catalog is shot at 59.94 fps (drone slow-mo / cinematic).
At 720p with a 2 Mbps target, x264 has to spread bits across 60 frames/s,
producing peaky VBR bursts that overflow the decode buffer on cellular —
the symptom is a "play half a second / pause / play half a second"
lurching pattern, most visible on high-motion 60 fps clips.

`encode_and_upload.sh`'s mobile filter therefore includes `,fps=30`. The
filter drops frames if source is >30; it's a no-op for 30 fps sources.
The desktop encode is `-c copy`, so full-res keeps original 60 fps.

If a NEW clip ever lurches in production: probe its R2 mobile file with
`ffprobe -show_entries stream=r_frame_rate`. If it reports `60000/1001`,
re-run `encode_and_upload.sh --force-mobile` for that clip — the current
script handles 60 fps correctly.

Currently-known 60 fps clips (all already re-encoded with the fix):
`06 14 16 23 26 29 30 35 38 42 45 46 47`.

## Conventions

- Commits: short imperative subject prefixed with `feat:`, `fix:`, or
  similar (see `git log` for style).
- Don't reintroduce a Vercel `/videos/*` rewrite — it caused the original
  bandwidth-cap issue. If corporate networks block R2 again (the original
  reason for the rewrite, see commit `b30998d`), the right fix is a custom
  subdomain on a domain we own (e.g. `videos.pjloury.com`), not re-proxying
  through Vercel.
- The R2 endpoint and AWS profile (`r2`) are referenced in
  `encode_and_upload.sh` — credentials live in `~/.aws/credentials`.
- PostHog telemetry is wired into `index.html` (`POSTHOG_KEY` constant).
  It's a public client key and safe to leave in the source.

## Useful one-liners

Verify cache header on a video:
```bash
curl -sI https://pub-abee44b9f56049338f38452f0835b88f.r2.dev/video-02-mobile.mp4 \
  | grep -i cache-control
```

List R2 contents:
```bash
aws s3 ls s3://drone-footage/ --profile r2 \
  --endpoint-url https://73fc4c58d8b8e9d05a8410bde37ff80d.r2.cloudflarestorage.com
```
