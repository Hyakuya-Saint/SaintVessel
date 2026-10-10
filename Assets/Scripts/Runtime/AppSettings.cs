using System;
using System.IO;
using UnityEngine;

namespace SaintVessel
{
    public enum BackgroundMode { Neutral, Gradient, Image, GreenScreen, Transparent }

    /// <summary>All user-tweakable settings; persisted as JSON in persistentDataPath.</summary>
    [Serializable]
    public sealed class AppSettings
    {
        // ---- tracking input
        public bool useFrontCamera = true;
        public bool flipCameraImage = false;   // only if your device delivers a mirrored analysis frame
        public bool useGpuDelegate = false;    // MediaPipe GPU delegate (experimental, falls back to CPU)
        public bool trackBody = true;
        public bool trackFace = true;
        public bool trackLegs = false;         // off by default: most desk/webcam setups don't show legs
        public bool mirror = true;             // true = avatar acts like a mirror, false = avatar copies you

        // ---- smoothing (One Euro filter): lower minCutoff = smoother, higher beta = less lag on fast moves
        public float bodyMinCutoff = 1.5f;
        public float bodyBeta = 1.0f;
        public float faceMinCutoff = 2.5f;
        public float faceBeta = 2.0f;
        public float followSpeed = 28f;        // render-rate interpolation toward the filtered target

        // ---- retargeting
        public float poseDepthScale = 1f;      // <1 damps noisy monocular depth
        public float fingerCurlDeg = 22f;      // relaxed hand (pose model has no finger tracking)
        public float mouthGain = 1.2f;
        public float emotionStrength = 0.35f;
        public float browGain = 1f;
        public float gazeGain = 110f;
        public bool swapEyes = false;          // flip if left wink drives the right eye
        public bool invertGazeYaw = false;
        public bool invertGazePitch = false;
        public bool idleBlink = true;

        // ---- view
        public BackgroundMode background = BackgroundMode.Neutral;
        public Color gradientTop = new Color(0.16f, 0.20f, 0.32f, 1f);
        public Color gradientBottom = new Color(0.55f, 0.40f, 0.60f, 1f);
        public float avatarScale = 1f;
        public float avatarYaw = 0f;
        public float cameraDistance = 2.4f;
        public float cameraHeight = 1.1f;
        public float cameraLookHeight = 1.05f;
        public float cameraFov = 28f;
        public bool showDebug = false;

        static string PathOnDisk => System.IO.Path.Combine(Application.persistentDataPath, "settings.json");

        public static AppSettings Load()
        {
            try
            {
                if (File.Exists(PathOnDisk))
                    return JsonUtility.FromJson<AppSettings>(File.ReadAllText(PathOnDisk)) ?? new AppSettings();
            }
            catch (Exception e) { Debug.LogWarning("Settings load failed: " + e.Message); }
            return new AppSettings();
        }

        public void Save()
        {
            try { File.WriteAllText(PathOnDisk, JsonUtility.ToJson(this, true)); }
            catch (Exception e) { Debug.LogWarning("Settings save failed: " + e.Message); }
        }
    }
}
