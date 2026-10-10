using UnityEngine;

namespace SaintVessel
{
    /// <summary>Touch-friendly IMGUI panel. Tap the top-right corner to bring the UI back after "Hide UI".</summary>
    public sealed class SettingsUI : MonoBehaviour
    {
        AppSettings _s;
        TrackingService _tracking;
        AvatarController _avatar;
        EnvironmentController _env;

        bool _open, _hidden, _dirty;
        int _tab;
        float _fps, _fpsT;
        int _frames;
        static readonly string[] Tabs = { "Tracking", "Face", "View", "Info" };

        public void Init(AppSettings s, TrackingService t, AvatarController a, EnvironmentController e)
        {
            _s = s; _tracking = t; _avatar = a; _env = e;
        }

        void Update()
        {
            _frames++; _fpsT += Time.unscaledDeltaTime;
            if (_fpsT >= 0.5f) { _fps = _frames / _fpsT; _frames = 0; _fpsT = 0f; }

            if (_hidden && Input.GetMouseButtonDown(0))
            {
                Vector2 p = Input.mousePosition;
                if (p.x > Screen.width - 140 && p.y > Screen.height - 140) _hidden = false;
            }
        }

        void OnApplicationPause(bool paused) { if (paused && _dirty) Save(); }

        void Save() { _s.Save(); _dirty = false; }

        float Slider(string label, float v, float min, float max)
        {
            GUILayout.BeginHorizontal();
            GUILayout.Label(label, GUILayout.Width(150));
            float n = GUILayout.HorizontalSlider(v, min, max, GUILayout.ExpandWidth(true), GUILayout.Height(26));
            GUILayout.Label(n.ToString("0.00"), GUILayout.Width(44));
            GUILayout.EndHorizontal();
            return n;
        }

        bool Toggle(string label, bool v) => GUILayout.Toggle(v, " " + label, GUILayout.Height(28));

        void OnGUI()
        {
            if (_s == null || _hidden) return;
            float sc = Mathf.Max(1f, Mathf.Min(Screen.width, Screen.height) / 420f);
            GUI.matrix = Matrix4x4.Scale(new Vector3(sc, sc, 1f));
            float W = Screen.width / sc, H = Screen.height / sc;

            if (_avatar != null && !_avatar.Ready)
                GUI.Label(new Rect(10, H * 0.45f, W - 20, 60), _avatar.LoadStatus);

            if (_s.showDebug)
                GUI.Label(new Rect(8, 4, W - 80, 70),
                    $"render {_fps:0} fps | tracking {_tracking.TrackingFps:0} fps\n{_tracking.Status}\n{_avatar.LoadStatus} {_env.BackgroundNote}");

            if (GUI.Button(new Rect(W - 66, 6, 60, 34), _open ? "Close" : "Menu"))
            {
                _open = !_open;
                if (!_open && _dirty) Save();
            }
            if (!_open) return;

            var panel = new Rect(6, 44, W - 12, Mathf.Min(H - 52, 430));
            GUI.Box(panel, GUIContent.none);
            GUILayout.BeginArea(new Rect(panel.x + 8, panel.y + 6, panel.width - 16, panel.height - 12));
            _tab = GUILayout.Toolbar(_tab, Tabs, GUILayout.Height(30));
            GUI.changed = false;

            switch (_tab)
            {
                case 0: TabTracking(); break;
                case 1: TabFace(); break;
                case 2: TabView(); break;
                default: TabInfo(); break;
            }
            if (GUI.changed) _dirty = true;
            GUILayout.EndArea();
        }

        void TabTracking()
        {
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("Start / restart camera", GUILayout.Height(32))) _tracking.StartTracking();
            if (GUILayout.Button("Stop", GUILayout.Height(32))) _tracking.StopTracking();
            GUILayout.EndHorizontal();
            _s.mirror = Toggle("Mirror mode (avatar acts like a mirror)", _s.mirror);
            _s.trackBody = Toggle("Track body", _s.trackBody);
            _s.trackFace = Toggle("Track face", _s.trackFace);
            _s.trackLegs = Toggle("Track legs (stand back so legs are visible)", _s.trackLegs);
            _s.useFrontCamera = Toggle("Front camera (restart camera to apply)", _s.useFrontCamera);
            _s.flipCameraImage = Toggle("Flip camera image (if left/right is wrong)", _s.flipCameraImage);
            _s.useGpuDelegate = Toggle("GPU delegate (experimental, restart camera)", _s.useGpuDelegate);
            _s.bodyMinCutoff = Slider("Body smoothing", _s.bodyMinCutoff, 0.2f, 5f);
            _s.bodyBeta = Slider("Body responsiveness", _s.bodyBeta, 0f, 5f);
            _s.faceMinCutoff = Slider("Face smoothing", _s.faceMinCutoff, 0.5f, 8f);
            _s.faceBeta = Slider("Face responsiveness", _s.faceBeta, 0f, 8f);
            _s.followSpeed = Slider("Follow speed", _s.followSpeed, 8f, 60f);
        }

        void TabFace()
        {
            _s.mouthGain = Slider("Mouth gain", _s.mouthGain, 0.5f, 2.5f);
            _s.emotionStrength = Slider("Emotion strength", _s.emotionStrength, 0f, 1f);
            _s.browGain = Slider("Eyebrow gain", _s.browGain, 0f, 2f);
            _s.gazeGain = Slider("Gaze gain", _s.gazeGain, 0f, 250f);
            _s.swapEyes = Toggle("Swap left/right eye (wink test)", _s.swapEyes);
            _s.invertGazeYaw = Toggle("Invert gaze horizontal", _s.invertGazeYaw);
            _s.invertGazePitch = Toggle("Invert gaze vertical", _s.invertGazePitch);
            _s.idleBlink = Toggle("Auto-blink when face is lost", _s.idleBlink);
            _s.poseDepthScale = Slider("Body depth scale", _s.poseDepthScale, 0.3f, 1.2f);
            _s.fingerCurlDeg = Slider("Relaxed finger curl", _s.fingerCurlDeg, 0f, 50f);
        }

        void TabView()
        {
            GUILayout.Label("Background");
            _s.background = (BackgroundMode)GUILayout.Toolbar((int)_s.background,
                new[] { "Neutral", "Gradient", "Image", "Green", "Alpha" }, GUILayout.Height(30));
            if (_s.background == BackgroundMode.Image && GUILayout.Button("Reload background image")) _env.ReloadBackgroundImage();
            if (_s.background == BackgroundMode.Gradient)
            {
                _s.gradientTop = ColorRow("Top", _s.gradientTop);
                _s.gradientBottom = ColorRow("Bottom", _s.gradientBottom);
            }
            _s.avatarScale = Slider("Avatar scale", _s.avatarScale, 0.5f, 1.5f);
            _s.avatarYaw = Slider("Avatar turn", _s.avatarYaw, -60f, 60f);
            _s.cameraDistance = Slider("Camera distance", _s.cameraDistance, 0.8f, 6f);
            _s.cameraHeight = Slider("Camera height", _s.cameraHeight, 0.2f, 2f);
            _s.cameraLookHeight = Slider("Look-at height", _s.cameraLookHeight, 0.2f, 1.8f);
            _s.cameraFov = Slider("Field of view", _s.cameraFov, 15f, 60f);
            if (GUILayout.Button("Hide UI (tap top-right corner to restore)", GUILayout.Height(32))) { _hidden = true; _open = false; Save(); }
        }

        Color ColorRow(string label, Color c)
        {
            GUILayout.BeginHorizontal();
            GUILayout.Label(label, GUILayout.Width(60));
            c.r = GUILayout.HorizontalSlider(c.r, 0f, 1f, GUILayout.Height(22));
            c.g = GUILayout.HorizontalSlider(c.g, 0f, 1f, GUILayout.Height(22));
            c.b = GUILayout.HorizontalSlider(c.b, 0f, 1f, GUILayout.Height(22));
            GUILayout.EndHorizontal();
            return c;
        }

        void TabInfo()
        {
            _s.showDebug = Toggle("Show debug overlay", _s.showDebug);
            GUILayout.Label("Tracking: " + _tracking.Status);
            GUILayout.Label("Avatar: " + _avatar.LoadStatus);
            GUILayout.Label("Custom models: drop a .vrm into\n" + Application.persistentDataPath + "/Models");
            GUILayout.Label("Background image: background.png in\n" + Application.persistentDataPath);
            if (GUILayout.Button("Reset all settings", GUILayout.Height(30)))
            {
                var d = new AppSettings();
                JsonUtility.FromJsonOverwrite(JsonUtility.ToJson(d), _s);
                _dirty = true;
            }
        }
    }
}
