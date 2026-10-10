using System.Collections;
using UnityEngine;
#if UNITY_ANDROID && !UNITY_EDITOR
using UnityEngine.Android;
#endif

namespace SaintVessel
{
    /// <summary>
    /// Owns the camera/tracking pipeline. On Android it talks to the Java TrackingBridge (CameraX + MediaPipe).
    /// In the Unity editor (or any non-Android platform) it plays a synthetic performance so the avatar can be tested.
    /// </summary>
    public sealed class TrackingService : MonoBehaviour
    {
        public readonly TrackingFrame Frame = new TrackingFrame();
        public string Status { get; private set; } = "idle";
        public float TrackingFps { get; private set; }
        public bool Running { get; private set; }

        AppSettings _s;
        bool _hasNew;
        int _fpsCount;
        float _fpsT, _simT, _statusT;

#if UNITY_ANDROID && !UNITY_EDITOR
        AndroidJavaObject _bridge;
        bool _permGranted, _permDenied;
#endif

        public void Init(AppSettings s)
        {
            _s = s;
            StartTracking();
        }

        public bool ConsumeNew()
        {
            bool n = _hasNew;
            _hasNew = false;
            return n;
        }

        public void StartTracking()
        {
            StopAllCoroutines();
            StartCoroutine(StartRoutine());
        }

        public void StopTracking()
        {
            StopAllCoroutines();
#if UNITY_ANDROID && !UNITY_EDITOR
            if (_bridge != null) { _bridge.Call("stop"); }
#endif
            Running = false;
            Status = "stopped";
        }

        IEnumerator StartRoutine()
        {
            Running = false;
#if UNITY_ANDROID && !UNITY_EDITOR
            if (!Permission.HasUserAuthorizedPermission(Permission.Camera))
            {
                Status = "requesting camera permission";
                _permGranted = _permDenied = false;
                var cb = new PermissionCallbacks();
                cb.PermissionGranted += _ => _permGranted = true;
                cb.PermissionDenied += _ => _permDenied = true;
                cb.PermissionDeniedAndDontAskAgain += _ => _permDenied = true;
                Permission.RequestUserPermission(Permission.Camera, cb);
                while (!_permGranted && !_permDenied) yield return null;
                if (_permDenied) { Status = "camera permission denied (enable it in Android settings)"; yield break; }
            }

            try
            {
                if (_bridge == null)
                {
                    using (var up = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
                    using (var act = up.GetStatic<AndroidJavaObject>("currentActivity"))
                        _bridge = new AndroidJavaObject("com.saintvessel.tracking.TrackingBridge", act);
                }
                _bridge.Call("start", _s.useFrontCamera, _s.flipCameraImage, _s.useGpuDelegate);
                Running = true;
                Status = "starting camera";
            }
            catch (System.Exception e)
            {
                Status = "tracking bridge error: " + e.Message;
                Debug.LogError(e);
            }
#else
            Running = true;
            Status = "simulated tracking (editor)";
            yield return null;
#endif
        }

        void Update()
        {
            if (!Running) return;
            _fpsT += Time.unscaledDeltaTime;
            if (_fpsT >= 1f) { TrackingFps = _fpsCount / _fpsT; _fpsCount = 0; _fpsT = 0f; }

#if UNITY_ANDROID && !UNITY_EDITOR
            if (_bridge == null) return;
            float[] packet = _bridge.Call<float[]>("poll");
            if (packet != null && Frame.Parse(packet)) { _hasNew = true; _fpsCount++; }

            _statusT += Time.unscaledDeltaTime;
            if (_statusT > 1f) { _statusT = 0f; Status = _bridge.Call<string>("getStatus"); }
#else
            _simT += Time.unscaledDeltaTime;
            if (_simT >= 1f / 30f)
            {
                _simT = 0f;
                SimTracking.Fill(Frame, Time.unscaledTime);
                _hasNew = true;
                _fpsCount++;
            }
#endif
        }

        void OnApplicationPause(bool paused)
        {
            if (_s == null) return;
            if (paused) StopTracking(); else StartTracking();
        }

        void OnDestroy()
        {
#if UNITY_ANDROID && !UNITY_EDITOR
            if (_bridge != null) { _bridge.Call("stop"); _bridge.Dispose(); _bridge = null; }
#endif
        }
    }

    /// <summary>Synthetic performer used in the editor: waves the user's right arm, talks, blinks, turns the head.</summary>
    static class SimTracking
    {
        static Vector3 ToMp(Vector3 user) => new Vector3(-user.x, -user.y, -user.z); // user frame -> MediaPipe frame

        public static void Fill(TrackingFrame f, float t)
        {
            f.poseValid = f.faceValid = true;
            f.imgW = 480f; f.imgH = 640f;

            // ---- pose, in the user's frame (x = user's right, y = up, z = facing direction)
            var u = new Vector3[TrackingFrame.PoseCount];
            Quaternion tw = Quaternion.Euler(0f, Mathf.Sin(t * 0.7f) * 18f, 0f);
            u[23] = new Vector3(-0.10f, 0f, 0f);   // left hip
            u[24] = new Vector3(0.10f, 0f, 0f);    // right hip
            u[11] = tw * new Vector3(-0.20f, 0.50f, 0f);
            u[12] = tw * new Vector3(0.20f, 0.50f, 0f);

            float wave = Mathf.Sin(t * 3f);
            Vector3 lEl = new Vector3(-0.15f, -1f, 0.05f).normalized * 0.28f;
            Vector3 lWr = new Vector3(-0.05f, -1f, 0.25f).normalized * 0.25f;
            Vector3 rEl = new Vector3(0.7f, 0.45f, 0.15f).normalized * 0.28f;
            Vector3 rWr = new Vector3(0.15f + 0.35f * wave, 1f, 0.1f).normalized * 0.25f;
            u[13] = u[11] + lEl; u[15] = u[13] + lWr;
            u[14] = u[12] + rEl; u[16] = u[14] + rWr;
            u[17] = u[15] + lWr.normalized * 0.07f; u[19] = u[15] + lWr.normalized * 0.08f;
            u[18] = u[16] + rWr.normalized * 0.07f; u[20] = u[16] + rWr.normalized * 0.08f;
            for (int s = 0; s < 2; s++)
            {
                float x = s == 0 ? -0.10f : 0.10f;
                int hip = s == 0 ? 23 : 24;
                u[hip + 2] = new Vector3(x, -0.45f, 0f);
                u[hip + 4] = new Vector3(x, -0.90f, 0f);
                u[hip + 8] = new Vector3(x, -0.95f, 0.12f);
            }
            for (int i = 0; i < TrackingFrame.PoseCount; i++)
            {
                f.poseWorld[i] = ToMp(u[i]);
                f.poseVis[i] = (i >= 25 && i <= 32) ? 0f : 1f;   // legs "not visible"
            }

            // ---- face mesh: canonical points rotated by a head pose, projected to image space
            Quaternion head = Quaternion.Euler(Mathf.Sin(t * 0.5f) * 8f, Mathf.Sin(t * 0.9f) * 25f, Mathf.Sin(t * 0.6f) * 8f);
            const float scale = 1600f; // meters -> pixels
            void Put(int idx, Vector3 userLocal)
            {
                Vector3 raw = ToMp(head * userLocal) * scale;
                f.face[idx] = new Vector3(0.5f + raw.x / f.imgW, 0.4f + raw.y / f.imgH, raw.z / f.imgW);
            }
            float gx = Mathf.Sin(t * 0.8f) * 0.004f;
            float blinkH = Mathf.Abs(Mathf.Sin(t * 1.3f)) > 0.97f ? 0f : 0.006f;
            // eye group A (33/133/159/145/468) sits on the user's right, group B on the left
            Put(33, new Vector3(0.045f, 0.03f, 0f));  Put(133, new Vector3(0.015f, 0.03f, 0f));
            Put(159, new Vector3(0.030f, 0.03f + blinkH, 0f)); Put(145, new Vector3(0.030f, 0.03f - blinkH, 0f));
            Put(468, new Vector3(0.030f + gx, 0.03f, 0f));
            Put(263, new Vector3(-0.045f, 0.03f, 0f)); Put(362, new Vector3(-0.015f, 0.03f, 0f));
            Put(386, new Vector3(-0.030f, 0.03f + blinkH, 0f)); Put(374, new Vector3(-0.030f, 0.03f - blinkH, 0f));
            Put(473, new Vector3(-0.030f + gx, 0.03f, 0f));
            Put(10, new Vector3(0f, 0.09f, 0f));      Put(152, new Vector3(0f, -0.07f, 0f));

            System.Array.Clear(f.blend, 0, f.blend.Length);
            void B(string n, float v) { f.blend[System.Array.IndexOf(TrackingFrame.BlendNames, n)] = Mathf.Clamp01(v); }
            B("jawOpen", 0.35f + 0.35f * Mathf.Sin(t * 5f));
            float smile = 0.5f + 0.5f * Mathf.Sin(t * 0.5f);
            B("mouthSmileLeft", smile); B("mouthSmileRight", smile);
            float blink = blinkH == 0f ? 1f : 0f;
            B("eyeBlinkLeft", blink); B("eyeBlinkRight", blink);
            B("browInnerUp", 0.3f + 0.3f * Mathf.Sin(t * 0.4f));
        }
    }
}
