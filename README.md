# Saint Vessel

Android VTuber app: real-time full-body + face tracking from the phone camera drives a **VRM 1.0** avatar (`Saint.vrm`).
Built with Unity 2022.3 + UniVRM 1.0, tracking by MediaPipe Tasks (pose + face landmarkers) through a small CameraX/Java plugin.
GitHub Actions produces `SaintVessel.apk` on every push to `main`.

## Architecture

```
Front camera (CameraX, 640x480 RGBA, un-mirrored)
   └─ TrackingBridge.java ── MediaPipe PoseLandmarker (33 world landmarks + visibility)
                          └─ MediaPipe FaceLandmarker (478 mesh+iris landmarks, 52 blendshapes)
         one float[1626] packet, polled by Unity (JNI)
Unity (C#)
   TrackingService ─ TrackingFrame
   PoseSolver  : landmarks -> swing/basis rotations for the VRM *normalized humanoid* (One Euro filtered)
   FaceSolver  : head pose + gaze from mesh, visemes/blink/brows/emotions from blendshapes
   AvatarController : bone smoothing -> Vrm10 control rig; expressions; LookAt; brow morphs
   UniVRM 1.0  : copies control rig to the real skeleton in LateUpdate, then runs spring bones (hair, skirt, sleeves, bust)
   EnvironmentController / SettingsUI : camera, backgrounds, touch settings panel
```

## What the Saint.vrm file contains (and what that implies)

| Finding | Consequence |
|---|---|
| VRM **1.0** (`VRMC_vrm` 1.0, `VRMC_springBone`, `VRMC_materials_mtoon`) | Loaded with UniVRM 1.0 (`Vrm10`), not the 0.x loader |
| 54 humanoid bones incl. UpperChest, eyes, toes, all fingers | Full pose retarget possible; fingers get a relaxed curl (pose model has no finger tracking) |
| Raw bones carry non-identity local rotations (hips ~7° X, arms/shoulders small Z/Y) | **Never drive raw bones.** We drive UniVRM's normalized *control rig* (identical T-pose frames) and let UniVRM copy to the real skeleton |
| Model facing in Unity depends on UniVRM's axis conversion | Facing is **measured at runtime** from leg positions (`AvatarRig.Frame`), not assumed |
| 59 spring chains / 218 joints, 28 colliders (Hair, Skirt, Sleeve, Bust, TopsUpperArm) | Runs automatically inside UniVRM |
| Expressions: happy, angry, sad, relaxed, surprised, aa, ih, ou, ee, oh, blink, blinkLeft/Right, neutral. **No custom expressions** | Visemes + per-eye blink use VRM expressions; brows and a mouth-smile are driven by the VRoid morphs `Fcl_BRW_*`, `Fcl_MTH_Joy` directly. `happy` = `Fcl_ALL_Joy` closes the eyes, so emotion strength defaults to 0.35 |
| LookAt type is **bone**, ranges only 8–12° | Gaze is subtle by design; adjust "Gaze gain" |
| Face 2,737 verts + Body 15,121 verts, 2 MToon materials, 12 textures | Very light for mobile |
| `firstPerson` is empty | Irrelevant here (third-person view) |

## Repo layout

```
.github/workflows/build-android.yml     CI: build + upload artifact + GitHub Release
scripts/fetch-models.sh                 downloads MediaPipe .task models
Packages/manifest.json                  UniVRM 0.125 (VRM 1.0) + burst/collections/mathematics
ProjectSettings/ProjectVersion.txt      Unity 2022.3.40f1
Assets/StreamingAssets/Saint.vrm        the avatar
Assets/Plugins/Android/SaintTracking.androidlib/   CameraX + MediaPipe plugin (Java, gradle)
Assets/Scripts/Runtime/*.cs             app code
Assets/Scripts/Editor/BuildScript.cs    player settings, scene generation, shader-variant anchor, build
```

## Setup

### A. Put it on GitHub and get an APK
1. Create a GitHub repo, push this folder to `main`.
2. Unity license for CI (game-ci): follow https://game.ci/docs/github/activation and add repo secrets
   `UNITY_LICENSE` (+ `UNITY_EMAIL`, `UNITY_PASSWORD`) — Settings → Secrets and variables → Actions.
3. Confirm the Unity version in `ProjectSettings/ProjectVersion.txt` exists as a game-ci image
   (https://game.ci/docs/docker/versions). Edit it if not (any 2022.3.x LTS).
4. Push. **Actions → Build Saint Vessel (Android APK)**. Download `SaintVessel-apk` from the run, or `SaintVessel.apk` from **Releases**.
5. Install on the phone (Android 8.0+, arm64), allow the camera.

### B. Build locally
1. Unity Hub → install 2022.3.x with **Android Build Support (SDK, NDK, OpenJDK)**.
2. `bash scripts/fetch-models.sh` (optionally `POSE_VARIANT=full`).
3. Open the project (first import downloads UniVRM from GitHub; needs git installed).
4. Menu **Saint Vessel → Build Android APK** → `build/Android/SaintVessel.apk`.
5. Press Play in the editor to test the avatar with a simulated performer (no camera needed there).

## First-run checklist on the phone
1. Stand/sit ~1.5 m from the phone, shoulders and face visible.
2. **Wink test:** close your left eye. If the avatar's wrong eye closes → Menu → Face → *Swap left/right eye*.
3. **Mirror test:** raise your right hand. Mirror mode (default) raises the avatar's left hand (as in a mirror); turn it off to copy you.
4. If everything is left/right reversed → Tracking → *Flip camera image*.
5. Jitter → lower *Body/Face smoothing*; lag → raise *responsiveness*.
6. Legs: enable *Track legs* only when your whole body is in frame.

## Customizing
- Other avatar: copy a `.vrm` to `<Android/data/com.saintvessel.app/files>/Models/` (first file wins).
- Background image: `background.png` in the same files folder, then View → Image.
- Green screen: View → Green (#00B140) and capture the screen (scrcpy/OBS, screen cast). "Alpha" outputs alpha 0 but Android windows are opaque, so it only helps when a capture path preserves alpha.

## Known limits
- Monocular depth is noisy: arms pointing at the camera are the weakest case. Lower *Body depth scale* to calm it.
- No forearm/wrist twist, no finger tracking, no hip translation (crouch/jump) and no foot planting/IK.
- Sources of left/right ambiguity (MediaPipe blendshape side naming, VRM left/right eye) are exposed as toggles instead of guessed.
- Written without access to Unity or the network: see "Things to verify" below.

## Things to verify on the first build
1. UniVRM tag `v0.125.0` resolves (https://github.com/vrm-c/UniVRM/releases). If you change it, check that
   `Vrm10.LoadBytesAsync(bytes, false, ControlRigGenerationOption.Generate, true)` in `AvatarController.cs` still matches.
2. `Vrm10Instance.LookAtTargetType`/`Runtime.LookAt.SetYawPitchManually`, `Runtime.ControlRig.GetBoneTransform`,
   `Runtime.Expression.SetWeight`, `ExpressionKey.*` — API names used from UniVRM 1.0.
3. `com.google.mediapipe:tasks-vision:0.10.14`, CameraX 1.3.4, compileSdk 34 (needs Android SDK platform 34; adjust `build.gradle` and `AndroidApiLevelAuto` if the CI image has another).
4. Avatar not pink → shader variants stripped; check the build log for "ShaderVariantAnchor: N materials anchored".
