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
- `encode_and_upload.sh` — three-step pipeline per clip: 720p@2M H.264
  mobile, faststart-muxed desktop, 720p poster JPG. Uploads all three to R2
  with the long cache header. Flags:
    - `--force-mobile` — re-encode mobile even if already in R2 (use after
      changing the bitrate ladder)
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

## Encoding gotchas

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
