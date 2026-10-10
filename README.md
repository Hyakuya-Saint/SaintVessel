# Saint Vessel (Godot 4)

Android VTuber app: real-time full-body + face tracking from the phone camera drives a **VRM 1.0** avatar (`Saint.vrm`).
Godot 4.3 (GL Compatibility renderer) + MediaPipe Tasks through a small Godot Android plugin (CameraX + Java).
GitHub Actions builds `SaintVessel.apk` on every push to `main`. **No Unity, no license, no secrets required.**

## Architecture

```
Front camera (CameraX, 640x480 RGBA, un-mirrored)
  └─ SaintTracking plugin (Java)
       ├─ MediaPipe PoseLandmarker  (33 world landmarks + visibility)
       └─ MediaPipe FaceLandmarker  (478 mesh+iris landmarks, 52 blendshapes)
     -> one float[1626] packet, polled from GDScript every frame
Godot (GDScript)
  tracking_service.gd  Android plugin / desktop simulator, camera permission
  vrm_model.gd         loads the .vrm with GLTFDocument, reads VRMC_* JSON itself (humanoid, expressions, look-at,
                       springs, MToon params) -> no addon needed
  avatar_rig.gd        rest data + facing measured from the legs; writes bone poses
  pose_solver.gd       landmarks -> limb directions + torso/hips frames, One Euro filtered, mirror/non-mirror
  face_solver.gd       head pose + gaze from the mesh, visemes/blink/brows/emotions from blendshapes
  spring_bones.gd      VRM 1.0 spring bones (hair, skirt, sleeves, bust) with sphere/capsule colliders
  mtoon_lite.gdshader  cel shader + inverted-hull outline from the MToon parameters
  environment_ctl.gd   camera + backgrounds (neutral / gradient / image / green screen / transparent)
  settings_ui.gd       touch settings panel
```

## What Saint.vrm contains (and what that implies)

| Finding | Consequence |
|---|---|
| VRM **1.0** (`VRMC_vrm`, `VRMC_springBone`, `VRMC_materials_mtoon`) | Godot imports the mesh/skeleton/morphs; the VRM data is read from the JSON chunk by `vrm_model.gd` |
| 54 humanoid bones incl. UpperChest, eyes, toes, all fingers | Full pose retarget; fingers get a relaxed curl (the pose model has no finger tracking) |
| Raw bones carry non-identity local rotations (hips ~7° X, arms/shoulders small Z/Y) | Never assume "identity = T-pose": every target is `delta * rest_global`, converted to a local pose with the parent's current rotation |
| Model facing in Godot is not assumed | Measured from the leg layout (`AvatarRig.frame_q`) |
| 59 spring chains / 218 joints, 28 colliders | Own GDScript simulation (`spring_bones.gd`); toggles in View tab if a phone struggles |
| Expressions: happy, angry, sad, relaxed, surprised, aa/ih/ou/ee/oh, blink, blinkLeft/Right. **No custom expressions** | Visemes + per-eye blink use VRM expression binds; brows and a smile shape are driven through the VRoid morphs `Fcl_BRW_*`, `Fcl_MTH_Joy`. `happy` (= `Fcl_ALL_Joy`) closes the eyes, so emotion strength defaults to 0.35 |
| LookAt is **bone**-type with 8–12° range | Eye bones are rotated directly and clamped to those ranges, so gaze is subtle by design |
| ~18k vertices, 2 MToon materials | Light for mobile |

## Repo layout

```
.github/workflows/build-android.yml   CI: plugin AAR -> Godot export -> artifact + GitHub Release
project.godot, export_presets.cfg     Godot 4.3, GL Compatibility, Android preset (gradle build, arm64, API 26-34)
models/Saint.vrm                      the avatar (exported via include_filter="*.vrm")
scripts/ shaders/ scenes/             app code
plugin/                               Godot Android plugin (Gradle project -> AAR, bundles the MediaPipe models)
android/plugins/SaintTracking.gdap    plugin descriptor + remote dependencies (MediaPipe, CameraX)
tools/                                fetch-models.sh, build-plugin.sh, ci-*.sh
```

## Setup

### A. GitHub APK build (nothing to configure)
1. Push this folder to the `main` branch of your repo.
2. Actions → **Build Saint Vessel (Android APK, Godot)**. Download `SaintVessel-apk` from the run, or `SaintVessel.apk` from **Releases**.
3. Install on the phone (Android 8.0+, arm64) and allow the camera.
4. Optional, for updates that install over older builds: add secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_USER`,
   `ANDROID_KEYSTORE_PASSWORD`. Without them CI signs with a throw-away key, so uninstall the old build first.

### B. Local build
1. Install Godot 4.3 + export templates, JDK 17, Android SDK (platform 34, build-tools 34.0.0), Gradle 8.5.
2. `bash tools/fetch-models.sh` (optionally `POSE_VARIANT=full`), then `bash tools/build-plugin.sh`.
3. Open the project in Godot → **Project → Install Android Build Template**, set the SDK/JDK paths in Editor Settings.
4. Project → Export → Android → Export Project. (Plain Play on desktop uses a simulated performer, no camera.)

## First-run checklist on the phone
1. Stand/sit ~1.5 m from the phone with shoulders and face visible.
2. **Wink test:** close your left eye. If the avatar's wrong eye closes → Menu → Face → *Swap left/right eye*.
3. **Mirror test:** raise your right hand. Mirror mode (default) raises the avatar's left hand; turn it off to copy you.
4. Everything left/right reversed → Tracking → *Flip camera image*.
5. Jitter → lower *smoothing* values; lag → raise *responsiveness*.
6. Legs: enable *Track legs* only when your whole body is in frame.
7. Slow frame rate → turn off *Spring bone collisions* or *Spring bones* (View tab), or use `POSE_VARIANT=lite`.

## Customizing
- Other avatar: put a `.vrm` in `user://models/` (Android: `Android/data/com.saintvessel.app/files/models/`); the first file wins.
- Background image: `background.png` in the same files folder, then View → Image.
- Green screen: View → Green (#00B140) and capture the screen (scrcpy/OBS). *Transparent* outputs alpha 0, but Android windows are opaque, so it only helps with a capture path that keeps alpha.

## Known limits
- Monocular depth is noisy: arms pointing at the camera are the weakest case (lower *Body depth scale*).
- No forearm/wrist twist, no finger tracking, no hip translation (crouch/jump), no foot planting/IK.
- MToon support is a lightweight approximation (base/shade colours, toony shading, rim, outline); no matcap or UV animation.
- Left/right ambiguities (MediaPipe blendshape naming, VRM eye sides) are exposed as toggles rather than guessed.

## Things to verify on the first build (written without access to Godot or the network)
1. Godot **4.3-stable** and the release asset names in `tools/ci-install-godot.sh`; `com.google.mediapipe:tasks-vision:0.10.14`; CameraX 1.3.4; `org.godotengine:godot:4.3.0.stable` (plugin compile dependency).
2. The preset option keys in `export_presets.cfg` (Godot ignores unknown keys; check *Project → Export* once in the editor and re-save if it shows warnings).
3. After importing, the log should list one `Skeleton3D` containing the hips. If the avatar's head and body move separately, the glTF importer created two skeletons (Face/Body skins) — tell me and I'll merge them in `vrm_model.gd`.
4. A grey/untextured avatar → toggle *toon_shader* off in `app_settings.gd` (or set it false in `user://settings.json`) to fall back to Godot's imported materials.
