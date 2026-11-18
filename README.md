# CVSAFE – Construction Site Occupational Safety & Autonomous Violation Detection Assistant

The project consists of four modules:

| Folder | Purpose | Technology |
| --- | --- | --- |
| `backend/` | AI server: image/video/stream analysis, incident workflow, analytics, PDF reports | Python, FastAPI, YOLO11 (Ultralytics), OpenCV, SQLite |
| `packages/cvsafe_core/` | Shared client core: domain models, HTTP API client, industrial theme, common widgets | Dart / Flutter package |
| `mobile/` | Field mobile application (`lib/main.dart`) for site managers | Flutter (Android, iOS, Web) |
| `web_panel/` | Desktop browser management panel (`lib/main.dart`) for administrators and OHS specialists | Flutter Web, Riverpod (`flutter_riverpod`), `go_router` |

- **Mobile app (`mobile/`)** is built for field site managers: receives real-time alerts, views annotated/raw evidence, logs field actions, and runs on-demand AI photo/video scans.
- **Web panel (`web_panel/`)** is built for office administrators and OHS specialists: manages cameras, draws polygonal danger/height zones interactively, manages subcontractors and users, inspects incidents with false-alarm reason codes, and exports analytics/PDF reports.
- **Shared core (`packages/cvsafe_core/`)** provides strongly typed models, `ApiClient`, theme tokens, and reusable UI components shared across both Flutter applications.

---

## 1. Running the AI Backend Server

Requirement: Python 3.10 or newer.

```bash
cd backend
python -m venv .venv
# Windows: .venv\Scripts\activate     macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
```

Start the server (`CVSAFE_DEMO=1` seeds a sample 7-day incident history instead of an empty database):

```bash
# macOS / Linux
CVSAFE_DEMO=1 uvicorn app.main:app --host 0.0.0.0 --port 8000
# Windows PowerShell
$env:CVSAFE_DEMO="1"; uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Verify: open `http://localhost:8000/docs` in your browser to inspect and test the interactive OpenAPI documentation.

### Users and Sign-In
On first startup, the server creates a default administrator account: **admin / cvsafe123**. Change this password from the **Users** page in the web panel after signing in.
When started with `CVSAFE_DEMO=1`, two additional demo accounts are seeded: **isg / cvsafe123** (OHS Specialist) and **saha / cvsafe123** (Site Manager).

| Role | Permissions |
| --- | --- |
| Administrator | Full access: camera CRUD, zone editor, subcontractor & user management (create, role/name update, activate/deactivate, password reset) |
| OHS Specialist | Camera zone drawing, subcontractor management, incident review & actions, analytics & PDF reports |
| Site Manager | Viewing and responding to alerts, field actions, AI Scan, analytics |

### Connecting a Camera
In the web panel, open **Cameras & Zones > Add Camera** and enter an RTSP stream URL in **Stream source**:

```
rtsp://user:password@192.168.1.21:554/stream1
```

If no physical IP camera is available, you can enter a local video file path (`C:/videos/site.mp4`). The file loops continuously like a live feed, generating live frames and automatic violation alerts.
`config.yaml` is read only once as initial seed data; subsequent changes made through the web panel are persisted in SQLite.

### Backend Tests
To run the full test suite (including end-to-end YOLO image/video tests), place two sample images containing people (`people.jpg` and `street.jpg`) in `backend/tests/samples/`, then run:

```bash
pytest -q tests
```

---

## 2. Running the Flutter Applications

Requirement: Flutter SDK 3.22 or newer (`flutter doctor` should report no issues).

### 2.1 Field Mobile App (`mobile/`)
On first setup, run the platform bootstrap script **once** to generate platform folders and configure camera/network permissions:

```bash
cd mobile
bash setup.sh                                          # macOS / Linux
powershell -ExecutionPolicy Bypass -File setup.ps1     # Windows
```

Then launch the mobile app:

```bash
flutter run
```

Tap the profile icon in the top-right corner to configure the server URL:

- **Android emulator:** `http://10.0.2.2:8000` (default)
- **Physical phone:** `http://<computer-lan-ip>:8000` (phone and computer must be on the same Wi-Fi network)
- **Web:** `flutter run -d chrome` with `http://localhost:8000`

If the backend is reachable, the sign-in screen opens; otherwise, the mobile app falls back to offline demo mode with a banner indicator.

### 2.2 Management Web Panel (`web_panel/`)
In a separate terminal, run the standalone web panel application:

```bash
cd web_panel
flutter pub get
flutter run -d chrome
```

Sign in with server URL `http://localhost:8000` (e.g., `admin` / `cvsafe123`).

| Route / Page | Description |
| --- | --- |
| **Dashboard** (`/dashboard`) | Compliance index, open alerts, hourly/daily violation trend chart, breakdown by violation type and camera, live camera health table |
| **Incidents** (`/incidents`, `/incidents/:id`) | Filterable incident log (status, violation type, camera, severity, search). Clicking a row opens the detail modal with AI/raw face-blurred evidence toggle, audit timeline, **Acknowledge**, **False Alarm** (with mandatory reason code & note), and field action chips |
| **Cameras & Zones** (`/cameras`, `/cameras/:id/zones`) | Camera management and live snapshots. **Zones** opens the interactive polygon editor supporting point-by-point drawing, corner dragging on existing zones, reference photo upload, and unsaved-changes protection |
| **Subcontractors** (`/subcontractors`) | Subcontractor registry, violation counters, and assigned camera mapping |
| **Reports** (`/reports`) | Period summary KPIs, subcontractor & camera breakdown tables, and one-click PDF report export |
| **Users** (`/users`) | Role-guarded administrator view: create users, edit display name/role, activate/deactivate accounts (`is_active`), reset passwords, and delete users (enforcing last-active-admin protection) |

---

## 3. Mobile Screens

| Screen | Description |
| --- | --- |
| **Alerts** | Open alerts (polled every 5s), filters (Critical / PPE / Zone / Resolved), Acknowledge, False Alarm, siren/broadcast/warning actions, and in-app notification banner |
| **Evidence** | Annotated vs. raw face-blurred evidence toggle, subcontractor, zone, tracking ID, legal citation, response actions, and incident timeline |
| **AI Scan** | Capture or pick a photo/video for on-demand analysis. Displays per-worker hardhat, vest, and harness status, zone intrusion, fall detection, and vehicle proximity |
| **Live CCTV** | 1 FPS AI-annotated camera feeds, 2x2 grid view, read-only zone list, and siren trigger |
| **Analytics** | Compliance index, scanned worker count, mean response time, PPE compliance rate, violation breakdown, subcontractor ranking, and PDF report |

## 4. How the AI Pipeline Works

1. **YOLO11-pose** detects workers and 17 skeletal keypoints (head, shoulders, hips, ankles).
2. **PPE check:** Uses trained weights at `weights/ppe.pt` when present; otherwise falls back to an HSV color heuristic for hardhat and high-visibility vest regions.
3. **YOLO11 (COCO)** detects site vehicles and trucks, raising proximity alerts when a worker enters the safety buffer.
4. **Rule engine:** Checks polygonal danger-zone intrusion (ankle midpoint inside polygon), safety harness requirement in work-at-height zones, and fall posture (torso angle when legs are visible).
5. **Video & stream tracking:** ByteTrack tracks worker IDs across frames. A violation triggers an incident only after persisting across consecutive frames and is deduplicated per worker/type cooldown window.
6. **KVKK / Privacy:** All stored and transmitted evidence images automatically blur detected face regions.

### Training the Custom PPE Model
To replace the heuristic fallback with a custom YOLO PPE detector targeting ≥85% mAP:

1. Download a YOLO-formatted PPE dataset (e.g., Construction Site Safety or SHWD).
2. Update the dataset path in `training/data.yaml`.
3. Run `python training/train_ppe.py --epochs 80` on a GPU machine or Colab.
4. Place the resulting `weights/ppe.pt` file in `backend/weights/`; `/health` will report `"mode": "ppe-model"` on restart.

## 5. Known Limitations & Next Steps
- **Push notifications:** Currently polls every 5 seconds while the client is open; Firebase Cloud Messaging (FCM) is planned for background mobile notifications.
- **Live video transport:** Uses 1 FPS annotated JPEG snapshots; WebRTC/HLS streaming can be added for low-latency continuous video.
- **Legal citations:** Provided for guidance; the OHS specialist should verify applicability per incident.
- **Hardware throughput:** CPU inference takes ~0.2–0.4s per frame; GPU or ONNX/TensorRT export is recommended for 4 simultaneous camera streams.

## 6. API Summary

| Method | Path | Description |
| --- | --- | --- |
| POST | `/auth/login` · `/auth/logout` · `/auth/password` | Sign in (`Bearer <token>`), sign out, or change own password |
| GET | `/health` | Model mode, active streams, and inference latency (public) |
| GET/POST/PATCH/DELETE | `/users` · `/users/{id}` | User listing, creation, name/role/active-status update (`PATCH`), password reset, deletion (admin) |
| POST/DELETE | `/cameras` · `/cameras/{id}` | Add, update, or remove cameras (admin) |
| PUT | `/cameras/{id}/zones` | Replace polygonal danger/height zones for a camera (admin, OHS) |
| POST / GET | `/cameras/{id}/reference` · `/cameras/{id}/frame` | Upload reference calibration image; fetch live/reference frame |
| POST/DELETE | `/subcontractors` | Manage subcontractors and camera assignments (admin, OHS) |
| GET | `/site` | Site metadata, cameras, zones, and subcontractors |
| GET | `/false_alarm_reasons` | Standardized false-alarm reason codes (`wrong_detection`, `authorised_person`, `reflection_shadow`, `other`) |
| GET | `/incidents?status=open&category=ppe&camera_id=CAM-01&offset=0` | Filtered, paginated incident list |
| GET | `/incidents/{id}` | Incident detail and audit timeline |
| POST | `/incidents/{id}/ack` · `/false_alarm` · `/action` | Acknowledge (`open -> acknowledged`), mark false alarm with `reason` & `note`, or log field action |
| POST | `/analyze/image` | On-demand image analysis (multipart: `file`, `camera_id`, `create_incidents`) |
| POST → GET | `/analyze/video` → `/jobs/{id}` | Asynchronous video analysis job with progress percentage |
| GET | `/cameras/{id}/snapshot` | Latest AI-annotated frame for a camera |
| GET | `/analytics?range=today\|week\|month` | Aggregated KPIs, trend series, and breakdowns |
| GET | `/reports/summary.pdf?range=week` | Generated PDF safety summary report |
