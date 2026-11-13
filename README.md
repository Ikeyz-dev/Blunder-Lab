# Blunder Lab

Paste a chess game (PGN). Stockfish, bundled inside the app, checks every
position, finds the moves where you gave away the most, and turns each one
into a "find the better move" puzzle with hints and an explanation.

## Build the APK with GitHub

1. Upload everything in this folder to a GitHub repo (make sure the hidden
   `.github/workflows/build-apk.yml` file is included).
2. Open the **Actions** tab -> **Build APK** -> wait for the green tick
   (first build is slow because it compiles Stockfish).
3. Open the finished run and download the **blunder-lab-apk** artifact.
   Unzip it and install `app-release.apk`.

To re-run without a new commit: Actions -> Build APK -> Run workflow.

## Layout

- `packages/`       patched copy of the Stockfish plugin (modern Gradle)
- `lib/chess/`     rules engine (moves, FEN, SAN, PGN), perft-tested
- `lib/analysis/`  mistake detection and puzzle building
- `lib/engine/`    Stockfish wrapper (UCI over FFI)
- `lib/screens/`   home, puzzle list, puzzle
- `lib/widgets/`   chess.com-style board
- `tool/`          desktop Dart scripts used to test the chess + puzzle logic

Piece artwork: "cburnett" set (GPL-2.0+/BSD/GFDL tri-licensed), via Lichess.
Stockfish is GPL-3.0; if you distribute the app publicly, the GPL applies.
