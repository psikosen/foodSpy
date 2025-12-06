# PlateDepth

Pastel-themed Flutter app for food volume estimation with native iOS camera, depth capture, and CoreML segmentation.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/setup.sh` | Validates local dependencies (Git, curl, unzip, Git LFS, Flutter) and prepares workspace directories (`models/`, `downloads/`). Fails with clear guidance if prerequisites are missing. |
| `scripts/download_models.sh` | Downloads the EdgeSAM `.mlmodel` into `models/`. Requires `EDGE_SAM_URL` to be exported. Supports optional `EDGE_SAM_SHA256` checksum validation. |
| `scripts/build.sh` | Runs `flutter pub get`, `flutter analyze`, and `flutter test`. On macOS it also executes `flutter build ios --no-codesign`; on other platforms it skips the iOS build gracefully. |
| `scripts/convert_edgesam.py` | Converts TorchScript EdgeSAM weights to a quantized `.mlmodel` (Float16) ready for Xcode ingestion. |
| `scripts/ci/run_checks.sh` | CI entrypoint that delegates to `scripts/build.sh`. |

### Usage

Run setup first to verify the toolchain:

```bash
./scripts/setup.sh
```

Download the EdgeSAM model (URL provided via `EDGE_SAM_URL`):

```bash
EDGE_SAM_URL="https://example.com/EdgeSAM.mlmodel" \
EDGE_SAM_SHA256="<optional-sha256>" \
./scripts/download_models.sh
```

Build the Flutter project:

```bash
./scripts/build.sh
```

## Task Tracker

See [`task.md`](task.md) for the current delivery checklist aligned with Jira tickets.
