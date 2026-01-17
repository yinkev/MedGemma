# MedASR Finder Quick Action (Right-Click Transcription)

This project includes an installer that creates a Finder Quick Action for right-click transcription.

## Install (Recommended)

1. Run setup first:

```bash
./setup.sh
```

2. Install the Quick Action:

```bash
./workflows/install-quick-action.sh
```

This script generates a `.workflow` bundle with the correct absolute path to this repo and installs it to:

- `~/Library/Services/`

3. Enable it:

- System Settings -> Extensions -> Finder -> enable `MedASR Transcribe`

## Use

1. Right-click any audio/video file in Finder
2. Quick Actions -> `MedASR Transcribe`
3. Wait for the completion notification
4. Outputs are written next to the input file (default is timestamped `.txt`; see below)

## What It Runs

The workflow executes the repo-local wrapper:

- `bin/medasr-transcribe`

That wrapper selects the correct venv and runs the Python entrypoint.

## Output Notes

By default this project writes a timestamped transcript in `.txt` format. Other formats are available via CLI flags when running manually.

## Uninstall

```bash
rm -rf "$HOME/Library/Services/MedASR Transcribe.workflow"
```

Then disable it in System Settings -> Extensions -> Finder.

## Troubleshooting

### Quick Action does not appear

1. Verify it's enabled:
   - System Settings -> Extensions -> Finder
2. Restart Finder:

```bash
killall Finder
```

### It runs but produces no output

- Confirm `bin/medasr-transcribe` runs from terminal on the same file.
- Confirm `ffmpeg` is installed (`brew install ffmpeg`).

### Permissions

- For system audio capture (not required for Quick Action): macOS Screen Recording permission is required for the terminal app.
