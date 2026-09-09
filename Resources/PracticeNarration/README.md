# Practice narration resources

Production narration delivered in `Maya1-P3-Narration-601-2026-08-20`.

- 60 practice folders
- 601 production MP3 cues
- mono, 24 kHz, 96 kbps
- production mapping in `manifest.json`

Do not rename or flatten the audio hierarchy. The manifest paths are relative
to the application resource root and use
`narration/audio/<practice-slug>/cue-XX.mp3`.

The MP3 files were encoded from the delivered 24 kHz, 16-bit PCM masters.
The original Maya1 WAV delivery remains outside the repository as the
lossless source and backup.

`tools/copy-practice-narration.sh` and the two narration `.xcfilelist` files
copy these resources into the application bundle while keeping Xcode user
script sandboxing enabled.
