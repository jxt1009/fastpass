# 2026-06-09 Crop/Zoom Modernization

Goal: replace the custom crop UI with a mature iOS cropper and improve zoom ergonomics in editable flows without changing API contracts.

Plan:
- Add `TOCropViewController` via Swift Package Manager to the iOS app target.
- Swap `PhotoCropView` from custom gesture rendering to a wrapper around `CropViewController` with square, locked crop behavior.
- Keep call-site behavior compatible by preserving avatar/car save flow and output sizing.
- Improve fullscreen avatar zoom interactions with pinch + double-tap zoom when a local image is available.
- Add targeted tests for crop context helper behavior and run focused verification + build-for-testing.

Status: completed in this track.
