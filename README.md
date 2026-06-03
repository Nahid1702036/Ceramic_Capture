# Ceramic Capture — Stage 1 Capture App

Flutter photogrammetry capture assistant for the Ceramic Digital-Twin Pipeline.

---

## Project Structure

```
ceramic_capture/
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── constants/app_constants.dart       — colours, pass configs
│   │   ├── models/capture_models.dart         — data classes + enums
│   │   └── services/
│   │       ├── yolo_service.dart              — TFLite / FastAPI dual-mode inference
│   │       ├── quality_analyzer.dart          — blur, exposure, duplicate checks
│   │       ├── coverage_engine.dart           — IMU → zone, coverage %
│   │       └── project_file_service.dart      — on-device folder + metadata
│   └── features/
│       ├── home/home_screen.dart
│       ├── camera/
│       │   ├── camera_screen.dart
│       │   ├── providers/camera_providers.dart
│       │   └── widgets/
│       │       ├── yolo_overlay.dart          — spotlight + soft border + label
│       │       ├── quality_hud.dart
│       │       ├── coverage_arc.dart
│       │       ├── pass_guide_banner.dart
│       │       └── capture_button.dart
│       ├── session/session_dashboard_screen.dart
│       └── export/services/pdf_report_service.dart
├── assets/
│   ├── models/          ← place yolov8_ceramic.tflite here
│   ├── icons/
│   └── sounds/
└── backend/
    ├── server.py        — FastAPI dev server (Ultralytics)
    └── export_tflite.py — exports yolo26m.pt → yolov8_ceramic.tflite
```

---

## First-time Setup

### 1 — Code generation (required before building)
```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```
This generates `lib/core/models/capture_models.g.dart` for JSON serialisation.

### 2 — TFLite model
Export or obtain `yolov8_ceramic.tflite` and place it at:
```
assets/models/yolov8_ceramic.tflite
```
To export from your trained weights on Zorin:
```bash
cd backend
pip install ultralytics tensorflow
python export_tflite.py --model yolo26m.pt --imgsz 640
# copies output to assets/models/yolov8_ceramic.tflite automatically
```

### 3 — Android permissions
Add to `android/app/src/main/AndroidManifest.xml` inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

### 4 — Run
```bash
flutter run                          # TFLite mode (prod default)
```

---

## Dev Mode (FastAPI on Zorin)

Edit `lib/features/camera/providers/camera_providers.dart`:
```dart
final service = YoloService(
  mode: InferenceMode.fastapi,
  fastapiHost: '192.168.x.x:8000',  // your Zorin IP
);
```
Start the server on Zorin:
```bash
cd backend
pip install fastapi uvicorn ultralytics pillow numpy
python server.py --model yolo26m.pt --host 0.0.0.0 --port 8000
```

---

## Camera Overlay — Spotlight Behaviour

When a `ceramic_object` is detected:
- **Vignette**: everything outside the bounding box fades to 72% black using a
  feathered cutout (`saveLayer` + `BlendMode.dstOut` + 22px blur). The transition
  is always soft — no hard edge.
- **Border**: a gentle glowing rounded rect (14px radius) with three concentric
  blur layers and dot corner accents frames the object.
- **Label pill**: centred below (or above if near the bottom of frame), shows
  `<piece name>  <confidence>%` in the orbit-blue colour.

Secondary detections (maker marks, signatures, stamps, foot rings, scale markers)
render as small colour-coded chip tags — visible but not competing with the main
spotlight.

When nothing is detected the overlay is transparent so the user can see the full
frame and reposition.

---

## YOLO Classes

| Index | Class            |
|-------|-----------------|
| 0     | ceramic_object  |
| 1     | maker_mark      |
| 2     | signature       |
| 3     | stamp           |
| 4     | foot_ring       |
| 5     | scale_marker    |
