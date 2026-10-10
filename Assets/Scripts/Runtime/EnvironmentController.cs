using System.IO;
using UnityEngine;

namespace SaintVessel
{
    /// <summary>Camera, lighting and background (neutral / gradient / image / green screen / transparent).</summary>
    public sealed class EnvironmentController : MonoBehaviour
    {
        public Camera Cam { get; private set; }
        public string BackgroundNote { get; private set; } = "";

        AppSettings _s;
        Transform _quad;
        Material _quadMat;
        Texture2D _grad, _img;
        BackgroundMode _lastMode = (BackgroundMode)(-1);
        Color _lastTop, _lastBottom;
        int _lastW, _lastH;
        float _lastFov;
        bool _reloadImage;

        public void Init(AppSettings s)
        {
            _s = s;
            var camGo = new GameObject("Main Camera") { tag = "MainCamera" };
            camGo.transform.SetParent(transform, false);
            Cam = camGo.AddComponent<Camera>();
            Cam.nearClipPlane = 0.05f;
            Cam.farClipPlane = 60f;
            Cam.allowHDR = false;

            var lightGo = new GameObject("Key Light");
            lightGo.transform.SetParent(transform, false);
            lightGo.transform.rotation = Quaternion.Euler(30f, 25f, 0f);
            var l = lightGo.AddComponent<Light>();
            l.type = LightType.Directional;
            l.intensity = 1.0f;
            l.shadows = LightShadows.None;

            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.55f, 0.55f, 0.55f);

            var q = GameObject.CreatePrimitive(PrimitiveType.Quad);
            Destroy(q.GetComponent<Collider>());
            q.name = "Background";
            _quad = q.transform;
            _quad.SetParent(Cam.transform, false);
            Shader sh = Shader.Find("Unlit/Texture");
            _quadMat = new Material(sh);
            q.GetComponent<MeshRenderer>().sharedMaterial = _quadMat;
            q.SetActive(false);
        }

        public void ReloadBackgroundImage() { _reloadImage = true; }

        /// <summary>Place the camera in front of the avatar, looking at it.</summary>
        public void Frame(Vector3 avatarPos, Vector3 facing)
        {
            facing.y = 0f;
            if (facing.sqrMagnitude < 1e-4f) facing = Vector3.back;
            facing.Normalize();
            Vector3 pos = avatarPos + facing * _s.cameraDistance + Vector3.up * _s.cameraHeight;
            Cam.transform.position = pos;
            Cam.transform.rotation = Quaternion.LookRotation(avatarPos + Vector3.up * _s.cameraLookHeight - pos, Vector3.up);
            Cam.fieldOfView = _s.cameraFov;
        }

        void LateUpdate()
        {
            if (_s == null) return;
            bool changed = _s.background != _lastMode || _s.gradientTop != _lastTop || _s.gradientBottom != _lastBottom
                           || Screen.width != _lastW || Screen.height != _lastH || _reloadImage
                           || !Mathf.Approximately(_s.cameraFov, _lastFov);
            if (!changed) return;
            _lastMode = _s.background; _lastTop = _s.gradientTop; _lastBottom = _s.gradientBottom;
            _lastW = Screen.width; _lastH = Screen.height; _lastFov = _s.cameraFov;
            ApplyBackground();
            _reloadImage = false;
        }

        void ApplyBackground()
        {
            BackgroundNote = "";
            Cam.clearFlags = CameraClearFlags.SolidColor;
            bool useQuad = false;

            switch (_s.background)
            {
                case BackgroundMode.Neutral:
                    Cam.backgroundColor = new Color(0.22f, 0.22f, 0.24f, 1f);
                    break;
                case BackgroundMode.GreenScreen:
                    Cam.backgroundColor = new Color(0f, 0.694f, 0.251f, 1f);   // #00B140 chroma green
                    break;
                case BackgroundMode.Transparent:
                    Cam.backgroundColor = new Color(0f, 0f, 0f, 0f);
                    BackgroundNote = "Alpha 0 output (needs a capture path that keeps alpha)";
                    break;
                case BackgroundMode.Gradient:
                    Cam.backgroundColor = Color.black;
                    BuildGradient();
                    _quadMat.mainTexture = _grad;
                    useQuad = true;
                    break;
                case BackgroundMode.Image:
                    Cam.backgroundColor = Color.black;
                    if (LoadImage()) { _quadMat.mainTexture = _img; useQuad = true; }
                    else { Cam.backgroundColor = new Color(0.22f, 0.22f, 0.24f, 1f); BackgroundNote = "Put background.png/.jpg in " + Application.persistentDataPath; }
                    break;
            }

            _quad.gameObject.SetActive(useQuad);
            if (useQuad)
            {
                float d = 40f;
                float h = 2f * d * Mathf.Tan(Cam.fieldOfView * 0.5f * Mathf.Deg2Rad);
                float w = h * Cam.aspect;
                _quad.localPosition = new Vector3(0f, 0f, d);
                _quad.localRotation = Quaternion.identity;
                _quad.localScale = new Vector3(w, h, 1f);
            }
        }

        void BuildGradient()
        {
            if (_grad == null) { _grad = new Texture2D(1, 256, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp }; }
            for (int y = 0; y < 256; y++) _grad.SetPixel(0, y, Color.Lerp(_s.gradientBottom, _s.gradientTop, y / 255f));
            _grad.Apply();
        }

        bool LoadImage()
        {
            foreach (var n in new[] { "background.png", "background.jpg", "background.jpeg" })
            {
                string p = Path.Combine(Application.persistentDataPath, n);
                if (!File.Exists(p)) continue;
                if (_img == null) _img = new Texture2D(2, 2, TextureFormat.RGBA32, false);
                if (_img.LoadImage(File.ReadAllBytes(p))) return true;
            }
            return false;
        }
    }
}
