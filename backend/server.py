# backend/server.py
#
# Ceramic Capture — Session-Aware Inference Server
#
# Runs on your Zorin machine.  Flutter app POSTs captured JPEG frames and
# receives YOLO detections + per-frame Kalman physics metadata.
#
# Session lifecycle (one session = one capture session in the Flutter app):
#
#   1.  POST /session/start          → session_id + server initialises
#                                       SpecKCalibrator + KalmanThermalEstimator
#                                       + FrameQualityGate for that session
#
#   2.  POST /predict/{session_id}   → YOLO detections + physics scalars
#                                       (rho_fil, k_mu, sigma2_k, trs, frame_valid)
#                                       Server keeps the previous frame in memory
#                                       so it can run the pair-wise calibrator.
#
#   3.  GET  /session/{session_id}/summary
#                                    → final Kalman state for FAPE reconstruction
#                                       written into the session metadata.json
#
#   4.  DELETE /session/{session_id} → clean up in-memory state
#
# Stateless fallback: POST /predict (no session_id) works exactly as before —
# returns only YOLO detections, no physics metadata. Safe for clients that
# haven't called /session/start yet.
#
# Usage:
#   pip install fastapi uvicorn ultralytics pillow numpy torch torchvision
#   python backend/server.py --model yolo26m.pt --host 0.0.0.0 --port 8000

import argparse
import io
import sys
import time
import uuid
import traceback
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

import numpy as np
from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from PIL import Image
import uvicorn
from ultralytics import YOLO

# ─── FAPE Captain 9 imports ───────────────────────────────────────────────────
# These are imported lazily so the server still starts even if torch is not
# installed (falls back to YOLO-only mode).
FAPE_AVAILABLE = False
try:
    import torch
    import torch.nn.functional as F
    # Add the project root to path so we can import from FAPE_captain9_v113
    sys.path.insert(0, str(Path(__file__).parent.parent))
    from FAPE_captain9_v113 import (
        SpecKCalibrator,
        KalmanThermalEstimator,
        FrameQualityGate,
    )
    FAPE_AVAILABLE = True
    print("[FAPE] SpecKCalibrator + KalmanThermalEstimator + FrameQualityGate loaded ✓")
except ImportError as _e:
    print(f"[FAPE] Not available ({_e}) — serving YOLO-only mode")

# ─── Class map (must match Flutter YoloClass enum order) ─────────────────────
CLASS_NAMES = [
    "ceramic_object",
    "maker_mark",
    "signature",
    "stamp",
    "foot_ring",
    "scale_marker",
]

# ─── Per-session state ────────────────────────────────────────────────────────

@dataclass
class SessionState:
    """
    All mutable state for one active capture session.

    calibrator  / kalman / quality_gate update with every frame pair.
    prev_gray   is the grayscale tensor of the last accepted frame —
                the calibrator always needs (frame_i, frame_j) pairs.
    frame_count counts every POST to /predict/{session_id}.
    physics_log is a list of per-frame dicts for the session summary.
    """
    calibrator:   Any          # SpecKCalibrator   | None
    kalman:       Any          # KalmanThermalEstimator | None
    quality_gate: Any          # FrameQualityGate  | None
    device_class: str          = "mobile"
    prev_gray:    Any          = None   # torch.Tensor (H,W) or None
    frame_count:  int          = 0
    physics_log:  List[Dict]   = field(default_factory=list)

# session_id (str) → SessionState
_sessions: Dict[str, SessionState] = {}

# ─── App setup ────────────────────────────────────────────────────────────────
app = FastAPI(title="Ceramic Capture — Session-Aware Inference Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST", "GET", "DELETE"],
    allow_headers=["*"],
)

model: Optional[YOLO] = None
model_path: str = "yolo26m.pt"


@app.on_event("startup")
async def load_model():
    global model
    path = Path(model_path)
    if not path.exists():
        print(f"[WARN] Model not found at {path} — using yolov8n as fallback")
        model = YOLO("yolov8n.pt")
    else:
        print(f"[INFO] Loading {path}…")
        model = YOLO(str(path))
        print(f"[INFO] Model loaded")


# ─── Health check ─────────────────────────────────────────────────────────────
@app.get("/")
async def health():
    return {
        "status": "ok",
        "model": model_path,
        "classes": CLASS_NAMES,
        "fape_available": FAPE_AVAILABLE,
        "active_sessions": len(_sessions),
    }


# ═════════════════════════════════════════════════════════════════════════════
# SESSION LIFECYCLE
# ═════════════════════════════════════════════════════════════════════════════

@app.post("/session/start")
async def session_start(request: Request) -> JSONResponse:
    """
    Initialise a new capture session.

    Body (JSON):
        {
          "session_id":   "optional_custom_id",   // auto-generated if omitted
          "device_class": "mobile"                 // mobile | dslr | webcam
        }

    Returns:
        { "session_id": "...", "fape_active": bool }

    Flutter should call this when the user taps "BEGIN CAPTURE" and store the
    returned session_id.  Pass it as a path parameter to every /predict call.
    """
    try:
        body = await request.json()
    except Exception:
        body = {}

    session_id   = body.get("session_id") or str(uuid.uuid4())[:8]
    device_class = body.get("device_class", "mobile")

    # Tear down any existing session with the same id
    _sessions.pop(session_id, None)

    if FAPE_AVAILABLE:
        calib_class = device_class if device_class in ("mobile", "dslr", "webcam") else "mobile"
        state = SessionState(
            calibrator   = SpecKCalibrator(device_class=calib_class),
            kalman       = KalmanThermalEstimator(device_class=calib_class),
            quality_gate = FrameQualityGate(
                blur_thresh=100.0, motion_thresh=40.0, clip_thresh=0.05,
                max_consecutive_skips=5, device_class=device_class,
            ),
            device_class = device_class,
        )
    else:
        # FAPE not available — create a minimal placeholder so the session_id
        # is still tracked and /predict still works in YOLO-only mode.
        state = SessionState(
            calibrator=None, kalman=None, quality_gate=None,
            device_class=device_class,
        )

    _sessions[session_id] = state
    print(f"[Session] started  id={session_id}  device={device_class}  "
          f"fape={FAPE_AVAILABLE}")

    return JSONResponse({
        "session_id":  session_id,
        "fape_active": FAPE_AVAILABLE,
        "device_class": device_class,
    })


@app.get("/session/{session_id}/summary")
async def session_summary(session_id: str) -> JSONResponse:
    """
    Return the final Kalman + calibrator state for this session.
    Flutter calls this before closing a session and writes the result
    into metadata.json so FAPE reconstruction gets the correct priors.

    Response keys that FAPE needs:
        rho_final       — KalmanThermalEstimator thermal noise floor
        k_mu_final      — SpecKCalibrator contrast mean (spec-K)
        sigma2_k_final  — SpecKCalibrator posterior uncertainty
        frame_count     — total frames processed
        valid_frames    — frames that passed FrameQualityGate
        gate_summary    — human-readable gate statistics
    """
    state = _sessions.get(session_id)
    if state is None:
        raise HTTPException(status_code=404, detail=f"Session {session_id!r} not found")

    if not FAPE_AVAILABLE or state.calibrator is None:
        return JSONResponse({
            "session_id":    session_id,
            "fape_active":   False,
            "frame_count":   state.frame_count,
            "message":       "FAPE not available — no physics metadata",
        })

    n_valid = state.quality_gate.n_valid if hasattr(state.quality_gate, "n_valid") else 0

    return JSONResponse({
        "session_id":      session_id,
        "fape_active":     True,
        "device_class":    state.device_class,
        "frame_count":     state.frame_count,
        "valid_frames":    n_valid,
        # ── Kalman thermal state ─────────────────────────────────────────
        "rho_final":       round(float(state.kalman.rho_fil), 6),
        # ── SpecK contrast state ─────────────────────────────────────────
        "k_mu_final":      round(float(state.calibrator.k_hat), 6),
        "sigma2_k_final":  round(float(state.calibrator.uncertainty), 6),
        # ── Gate statistics ───────────────────────────────────────────────
        "gate_summary":    state.quality_gate.summary()
                           if hasattr(state.quality_gate, "summary") else "n/a",
        # ── Per-frame log (last 5 frames for debugging) ───────────────────
        "recent_physics":  state.physics_log[-5:],
    })


@app.delete("/session/{session_id}")
async def session_delete(session_id: str) -> JSONResponse:
    """Free in-memory session state when the Flutter app is done."""
    removed = _sessions.pop(session_id, None)
    if removed is None:
        raise HTTPException(status_code=404, detail=f"Session {session_id!r} not found")
    print(f"[Session] closed   id={session_id}  frames={removed.frame_count}")
    return JSONResponse({"status": "closed", "session_id": session_id})


# ═════════════════════════════════════════════════════════════════════════════
# PREDICTION  (session-aware)
# ═════════════════════════════════════════════════════════════════════════════

@app.post("/predict/{session_id}")
async def predict_session(session_id: str, request: Request) -> JSONResponse:
    """
    Session-aware prediction: YOLO detections + Kalman physics metadata.

    Body: raw JPEG bytes (same as stateless /predict).

    Response:
    {
      "detections": [ { cls, confidence, x, y, w, h }, … ],
      "physics": {
        "frame_valid":  true,          // passed FrameQualityGate
        "rho_fil":      0.021,         // thermal noise floor
        "k_mu":         0.042,         // spec-K contrast mean
        "sigma2_k":     0.008,         // contrast uncertainty
        "trs":          0.12,          // motion proxy (0 = still)
        "blur_score":   312.4,
        "motion_score": 3.1,
        "clip_ratio":   0.001
      },
      "elapsed_ms": 18.3
    }

    The physics block is null when FAPE is unavailable or this is the first
    frame (no previous frame to form a pair yet).
    """
    state = _sessions.get(session_id)
    if state is None:
        raise HTTPException(
            status_code=404,
            detail=f"Session {session_id!r} not found. Call POST /session/start first."
        )
    return await _run_predict(request, state)


@app.post("/predict")
async def predict_stateless(request: Request) -> JSONResponse:
    """
    Stateless fallback — returns YOLO detections only, no physics.
    Keeps backward compatibility with clients that don't use sessions.
    """
    return await _run_predict(request, state=None)


# ─── Shared prediction logic ──────────────────────────────────────────────────

async def _run_predict(
    request: Request,
    state: Optional[SessionState],
) -> JSONResponse:

    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    body = await request.body()
    if not body:
        raise HTTPException(status_code=400, detail="Empty body")

    t0 = time.perf_counter()

    # ── Decode image ────────────────────────────────────────────────────────
    try:
        pil_image = Image.open(io.BytesIO(body)).convert("RGB")
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Invalid image: {exc}")

    W, H = pil_image.size

    # ── YOLO inference ───────────────────────────────────────────────────────
    results = model.predict(
        source=np.array(pil_image),
        conf=0.45,
        iou=0.5,
        verbose=False,
        imgsz=640,
    )

    detections: List[Dict[str, Any]] = []
    for result in results:
        if result.boxes is None:
            continue
        for box in result.boxes:
            cls_idx = int(box.cls[0])
            conf    = float(box.conf[0])
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            detections.append({
                "cls":        CLASS_NAMES[cls_idx] if cls_idx < len(CLASS_NAMES)
                              else f"class_{cls_idx}",
                "confidence": round(conf, 4),
                "x":          round(x1 / W, 6),
                "y":          round(y1 / H, 6),
                "w":          round((x2 - x1) / W, 6),
                "h":          round((y2 - y1) / H, 6),
            })

    # ── Kalman + calibrator update (session mode only) ───────────────────────
    physics = None
    if state is not None and FAPE_AVAILABLE and state.calibrator is not None:
        physics = _run_physics_update(state, pil_image)

    elapsed_ms = round((time.perf_counter() - t0) * 1000, 1)
    n_det = len(detections)
    print(f"[Predict] {n_det} det  {elapsed_ms}ms"
          + (f"  rho={physics['rho_fil']:.4f}  k={physics['k_mu']:.4f}"
             if physics else ""))

    return JSONResponse({
        "detections": detections,
        "physics":    physics,
        "elapsed_ms": elapsed_ms,
    })


def _run_physics_update(
    state: SessionState,
    pil_image: "Image.Image",
) -> Dict[str, Any]:
    """
    Run SpecKCalibrator + KalmanThermalEstimator + FrameQualityGate
    for one new captured frame.

    Needs the previous frame to form a pair — returns a neutral fallback
    on the very first frame of a session.
    """
    try:
        import torch

        # Convert to grayscale tensor [0,1] — same as FAPE inference loop
        gray_np  = np.array(pil_image.convert("L")).astype(np.float32) / 255.0
        frame_j  = torch.from_numpy(gray_np)          # current  (H, W)
        H_img, W_img = frame_j.shape

        state.frame_count += 1

        # ── First frame: no pair yet ──────────────────────────────────────
        if state.prev_gray is None:
            state.prev_gray = frame_j.clone()
            # Seed the calibrator's read-noise estimate using two copies
            state.calibrator.calibrate_read_noise(
                torch.stack([frame_j, frame_j], 0))
            physics = {
                "frame_valid":  True,
                "first_frame":  True,
                "rho_fil":      round(float(state.kalman.rho_fil), 6),
                "k_mu":         round(float(state.calibrator.k_hat), 6),
                "sigma2_k":     round(float(state.calibrator.uncertainty), 6),
                "trs":          0.0,
                "blur_score":   None,
                "motion_score": None,
                "clip_ratio":   None,
            }
            state.physics_log.append(physics)
            return physics

        frame_i = state.prev_gray    # previous frame (H, W)

        # ── Build pixel grid for probe positions ──────────────────────────
        N_PTS    = 128
        rand_y   = torch.randint(0, H_img, (N_PTS,)).float()
        rand_x   = torch.randint(0, W_img, (N_PTS,)).float()
        pixels_xy = torch.stack([rand_x, rand_y], dim=1)          # (128, 2)
        depth_proxy = frame_i[
            pixels_xy[:, 1].long().clamp(0, H_img - 1),
            pixels_xy[:, 0].long().clamp(0, W_img - 1)] + 0.5    # (128,)
        positions_01 = pixels_xy.clone()
        positions_01[:, 0] /= W_img
        positions_01[:, 1] /= H_img

        # ── FrameQualityGate ──────────────────────────────────────────────
        is_valid, blur_sc, motion_sc, clip_sc = state.quality_gate.check(
            frame_i, frame_j)

        if not is_valid:
            should_reset = state.quality_gate.register_skip()
            k_mu_fb, rho_fb, _p_k = state.quality_gate.get_fallback()
            physics = {
                "frame_valid":  False,
                "rho_fil":      round(rho_fb, 6),
                "k_mu":         round(k_mu_fb, 6),
                "sigma2_k":     round(float(state.calibrator.uncertainty), 6),
                "trs":          0.0,
                "blur_score":   round(blur_sc, 2),
                "motion_score": round(motion_sc, 2),
                "clip_ratio":   round(clip_sc, 4),
                "gate_reset":   should_reset,
            }
        else:
            # ── SpecKCalibrator Bayesian update ───────────────────────────
            k_mu, k_sig, trs = state.calibrator.update(
                frame_i, frame_j, state.kalman.rho_fil,
                depth_proxy=depth_proxy, positions_01=positions_01,
            )
            k_mu_fused = float(state.calibrator.k_fused_scalar)

            # ── KalmanThermalEstimator update ─────────────────────────────
            flat   = frame_i.flatten()
            n_dark = max(int(0.01 * flat.numel()), 100)
            Z_k    = max(float(
                torch.topk(flat, n_dark, largest=False).values
                .var(correction=0).item()), 1e-6)
            trs_s = float(trs) if np.isfinite(float(trs)) else 0.0
            rho, p_k, _ = state.kalman.update(Z_k, trs_s)

            if np.isnan(rho) or np.isnan(p_k):
                # NaN guard — use last valid fallback
                k_mu_fb, rho, _p_k = state.quality_gate.get_fallback()
                p_k = float(state.calibrator.uncertainty)
            else:
                state.quality_gate.update_valid(k_mu_fused, rho, p_k)

            physics = {
                "frame_valid":  True,
                "rho_fil":      round(float(rho), 6),
                "k_mu":         round(float(k_mu_fused), 6),
                "sigma2_k":     round(float(k_sig), 6),
                "trs":          round(float(trs_s), 4),
                "blur_score":   round(blur_sc, 2),
                "motion_score": round(motion_sc, 2),
                "clip_ratio":   round(clip_sc, 4),
            }

        # Advance the frame window
        state.prev_gray = frame_j.clone()
        state.physics_log.append(physics)
        return physics

    except Exception as exc:
        traceback.print_exc()
        # Never crash the prediction — return neutral physics
        return {
            "frame_valid":  False,
            "error":        str(exc),
            "rho_fil":      0.02,
            "k_mu":         0.05,
            "sigma2_k":     0.1,
            "trs":          0.0,
        }


# ─── Legacy quality check endpoint (unchanged) ───────────────────────────────
@app.post("/quality")
async def quality_check(request: Request) -> JSONResponse:
    import cv2
    body = await request.body()
    img_array = np.frombuffer(body, np.uint8)
    img = cv2.imdecode(img_array, cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise HTTPException(status_code=400, detail="Invalid image")
    small      = cv2.resize(img, (320, 240))
    lap        = cv2.Laplacian(small, cv2.CV_64F)
    sharpness  = float(lap.var())
    brightness = float(small.mean()) / 255.0
    flags = []
    if sharpness  < 80:    flags.append("blur")
    if brightness > 0.85:  flags.append("overexposure")
    if brightness < 0.15:  flags.append("underexposure")
    return JSONResponse({"sharpness": round(sharpness,2),
                         "exposure": round(brightness,4), "flags": flags})


# ─── Entry point ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ceramic Capture — Session Server")
    parser.add_argument("--model",  default="yolo26m.pt")
    parser.add_argument("--host",   default="0.0.0.0")
    parser.add_argument("--port",   type=int, default=8000)
    args = parser.parse_args()

    model_path = args.model

    fape_status = "✓ SpecKCalibrator + Kalman active" if FAPE_AVAILABLE else "✗ YOLO-only mode"

    print(f"╔══════════════════════════════════════════════════╗")
    print(f"║   Ceramic Capture — Session-Aware Server         ║")
    print(f"╠══════════════════════════════════════════════════╣")
    print(f"║  Model  : {args.model:<39}║")
    print(f"║  Host   : {args.host}:{args.port:<33}║")
    print(f"║  FAPE   : {fape_status:<39}║")
    print(f"╠══════════════════════════════════════════════════╣")
    print(f"║  POST /session/start                             ║")
    print(f"║  POST /predict/{{session_id}}  → det + physics    ║")
    print(f"║  GET  /session/{{session_id}}/summary             ║")
    print(f"║  DEL  /session/{{session_id}}                     ║")
    print(f"║  POST /predict               → det only (legacy) ║")
    print(f"╚══════════════════════════════════════════════════╝")

    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")
