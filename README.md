# Pēsu for macOS

Native Apple Silicon meeting intelligence built with Swift, AppKit, Core Audio, Apple Speech, Foundation Models, and SQLite.

## Current native milestone

- Approved Present → Past → Future → Stats → Recording → Summary flow
- Apple Calendar history restricted to one year; future events have no fixed cutoff and load in four-year chunks
- Per-calendar Settings switches persist locally and remove disabled sources from every meeting view and statistic; birthday, holiday and daylight-saving calendars start off
- High-confidence duplicate detection for Present and Future, with confirmed merge or extra-copy deletion in Apple Calendar
- Local meeting statistics with a 12-month intensity heatmap, busiest periods, average duration, and meeting-day life dots
- Supplied dog artwork used for the in-app brand mark and macOS app icon
- Local SQLite meeting history
- System-audio capture through an Apple Core Audio process tap; no screen content is captured
- Selected-microphone capture through Core Audio
- Separate local M4A files for system and microphone audio
- Live on-device Apple Speech transcription for both meeting audio and the user microphone
- Microphone selection in Settings, with System Default following macOS, manual device refresh, and safe fallback when a saved device is unavailable
- Apple Speech model preparation and Apple Intelligence meeting summaries run locally
- Decisions retain exact transcript evidence IDs
- Plain meeting briefs remove model formatting and decorative output before display
- Markdown and email export from every meeting summary
- Confirmed deletion removes a saved note, transcript, and its local audio files
- No account, webview, Electron runtime, or automatic meeting-content cloud path
- Explicit **Build from this meeting** consent flow can share only the displayed brief, decisions, selected action, and linked evidence with the selected AI provider in an isolated Daytona sandbox

During a recording, provisional speech appears immediately and is replaced by finalized transcript segments. Stopping saves the transcript and both audio tracks locally with the meeting.

## Build

```sh
./scripts/build-app.sh
open "build/Pēsu.app"
```

The first recording requests macOS system-audio, microphone and speech-recognition permissions. macOS remembers each choice until the user changes it in System Settings, so Pēsu does not request access again on later launches. It does not require screen-recording access. Apple may download the matching on-device speech model on first use. Full Xcode is required later for production signing and notarisation; this script creates an ad-hoc signed local review build. Rebuilding an ad-hoc signed review app can cause macOS to treat it as a changed app, while a stable Developer ID signature preserves its identity between releases.

## Daytona demo setup

The recording, transcription, and meeting-note flow remains local and works without Daytona. To enable the optional post-meeting build action:

1. Open Pēsu **Settings**, enter the Daytona API key, and choose **Save key**.
2. In the same Settings page, choose **OpenAI** or **Azure OpenAI** as the build provider. For OpenAI, save an OpenAI API key. For Azure OpenAI, save the Azure resource endpoint (`https://<resource>.openai.azure.com`), Responses API deployment name, and API key. Every provider credential is stored separately in macOS Keychain and is not added to Pēsu's database or meeting context.
3. Build and open Pēsu:

```sh
./scripts/build-app.sh
open "build/Pēsu.app"
```

The signed app bundle includes the localhost-only bridge and starts it on demand with a private per-launch token. Open a completed meeting in Pēsu, choose **Build from this meeting**, review the exact context and selected processor shown in the consent sheet, and create the workspace. Only the selected provider key is sent as private input to that one credential-bearing Daytona generator session, which is deleted before preview; it is never written to the sandbox environment, task files, generated output, or shell command. Azure endpoints are restricted to HTTPS `*.openai.azure.com` hosts and the sandbox outbound allowlist is narrowed to the selected provider host. The app streams real AI/Daytona progress and opens the signed preview when the generated static site is healthy.

## Share a test build

```sh
./scripts/package-dmg.sh
```

This creates an Apple-silicon disk image in `dist/` with Pēsu and an Applications shortcut. The current build requires macOS 26 or later. It is ad-hoc signed because this development Mac has no Developer ID Application certificate; a tester may need to Control-click Pēsu, choose Open, and confirm once. A warning-free public build requires Developer ID signing and Apple notarisation.
