# Changelog

## 2026-08-27

### Improved

- Fixed the new-recording sheet so the meeting-name field accepts keyboard input immediately.
- Removed the premature system alert sound when opening the meeting-name sheet.
- Added native Pēsu, File, Edit, and Window menus with standard macOS keyboard shortcuts.
- Meeting briefs now display as clean natural text without raw Markdown, quotation marks, emoji, decorative labels, or model section syntax.
- Decisions are separated from the brief and linked to supporting transcript segments.
- Existing local notes are cleaned when Pēsu opens, including older placeholder recording-status summaries.
- Evidence now defaults to a real transcript source and every transcript row can be selected for inspection.
- The meeting summary returns to Present instead of Past.
- Sidebar selection uses a tighter rounded treatment and the Pēsu logo is larger.
- The recording-name sheet and active recording screen use a simpler modern layout.

### Added

- Export a meeting as a Markdown file for AI-agent workflows.
- Create an email draft containing the meeting note through the macOS sharing service.
- Delete locally saved meetings with confirmation, including their note, transcript, and local audio files.
- Use the persistent menu-bar icon to start a recording, show or close the window, open Settings or About, check for updates, and quit Pēsu.
- Package an Apple-silicon test build as a drag-to-Applications disk image with a SHA-256 checksum.

### Distribution

- Removed the machine-specific Homebrew SQLite link so shared builds use the SQLite library included with macOS.

### Safety

- Email export only starts when the user selects it.
- Meeting deletion always requires confirmation and is limited to locally saved recordings.
