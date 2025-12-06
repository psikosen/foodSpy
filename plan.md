# Execution Plan

1. Scaffold Flutter project `PlateDepth` with iOS Swift bridge support and pastel theme; ensure permissions and MethodChannel/EventChannel setup.
2. Implement native iOS Swift modules for camera, depth, blur check, stability, and CoreML model interfaces (encoder/decoder), plus storage paths for captures.
3. Wire Flutter side: textures, UI (camera/stability overlay, segmentation overlay, selection modal), state management, DB integration, and volume calculation logic with tests.
4. Set up data layer with SQLite seed (density data) and smart sorting logic.
5. Provide scripts/pipelines for model download/conversion and update CI/build hooks; ensure task tracker updated.
6. Run available tests/lints via build script (noting environment limitations) and prepare PR metadata.
