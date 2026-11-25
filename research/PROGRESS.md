# Sanctify — Progress Log

## What works

| Feature | Status | Notes |
|---|---|---|
| Dylib injection via insert_dylib | ✓ Working | Use `insert_dylib` on decrypted IPA |
| Settings button (⚡ Sanctify) | ✓ Working | Hooks `RootSettingsViewController.viewDidLoad`, adds nav bar button |
| Auto-launch on subsequent opens | ✓ Working | `SanctifyAutoLaunch` NSUserDefaults flag; 1.5s delay after token ready |
| Token capture via OauthAccessTokenBridge | ✓ Working | Mangled class name: `_TtC24Connectivity_SessionImplP33_831B98CC28223E431E21CD27ADD20AF222OauthAccessTokenBridge` |
| Token capture via NSURLSessionTask.resume | ✓ Added | Fallback — fires on every Spotify network request; more reliable |
| Full UI overlay (tab bar, home, artists, library) | ✓ Working | `SanctifyRootVC` replaces `rootViewController` |
| Navigation, tab switching | ✓ Working | |

## What does NOT work

| Feature | Status | Notes |
|---|---|---|
| API content loading (top artists, recently played, playlists) | ✗ Broken | Calls `api.spotify.com/v1` with bearer token, returns empty — root cause unknown, debug label added to diagnose |
| Audio playback via SPTCorePlayer | ✗ Not attempted | Current `sanctifyPlay()` uses `openURL:` with `spotify:` URI — this navigates Spotify's own UI, not our overlay |

## Root cause hypotheses for empty content (ranked)

1. **Token not yet captured** when views load — `gToken` nil, `spotifyGET` returns early silently
2. **API returns HTTP error** (401/403) — token exists but doesn't have required scopes, or token format wrong
3. **Token is correct but `NSURLSession.sharedSession` blocked** — Spotify may intercept shared session traffic

## Next diagnostic step

Build and sideload with debug label. The yellow label on Home shows:
- `token: nil` → token capture broken
- `token: ABCD1234… | HTTP 401: …` → token invalid/wrong format
- `token: ABCD1234… | HTTP 403: …` → token lacks scope
- `token: ABCD1234… | Loading…` then nothing → network/session issue

## Architecture decisions

- **FairPlay**: Cannot extract audio outside Spotify process. Correct approach is to drive `SPTCorePlayer` from within the injected dylib.
- **Audio playback**: Must use `SPTCorePlayer.playContext:options:` — NOT `openURL:` with `spotify:` URIs. This is deferred until content loading is confirmed working.
- **SPTSettingsViewController**: Does not exist in modern Spotify. Use `RootSettingsViewController`.
- **EeveeSpotify bypass**: Eevee only patches product state flags (client-side). It does NOT touch the audio pipeline. Audio still goes through FairPlay inside AVContentKeySession.
- **Content availability**: Spotify CDN serves audio when OAuth token is valid — subscription check is client-side only. EeveeSpotify patches `SPTCoreProductState` to overlay Premium flags.

## Key class names

| Class | Purpose |
|---|---|
| `RootSettingsViewController` | Modern settings root (use this, not `SPTSettingsViewController`) |
| `SPTCoreProductState` | Premium/Free flag bag — EeveeSpotify patches this |
| `SPTCorePlayer` / `SPTPlayer` | Player facade — use `playContext:options:` to trigger playback |
| `BMBetamaxPlayerImpl` | Concrete player — do NOT hook directly (too close to DRM boundary) |
| `BMSpotifyMediaHLSURLProvider` | Resolves HLS URLs from `spclient.wg.spotify.com/track-playback/v1/config` |
| `_TtC24Connectivity_SessionImpl...OauthAccessTokenBridge` | OAuth token bridge (Swift, mangled name required) |
