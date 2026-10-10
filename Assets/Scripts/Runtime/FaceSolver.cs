using System;
using UnityEngine;

namespace SaintVessel
{
    /// <summary>Everything the face tracker drives on the avatar, already smoothed. Left/Right = the AVATAR's sides.</summary>
    public sealed class FaceState
    {
        public bool Valid;
        public Quaternion HeadLocal = Quaternion.identity;   // absolute, avatar-local frame
        public float BlinkL, BlinkR;
        public float Aa, Ih, Ou, Ee, Oh;
        public float Happy, Angry, Sad, Surprised;
        public float BrowAngry, BrowFun, BrowJoy, BrowSorrow, BrowSurprised, MthJoy;
        public float GazeYaw, GazePitch;   // degrees, +yaw = avatar's right, +pitch = up
    }

    /// <summary>
    /// MediaPipe face landmarks + ARKit-style blendshapes -> VRM expressions, head orientation and gaze.
    /// Head pose and gaze come from mesh landmarks (side-agnostic: eyes are classified by image x),
    /// mouth/brows/blink come from the 52 blendshapes.
    /// </summary>
    public sealed class FaceSolver
    {
        public readonly FaceState State = new FaceState();
        readonly AppSettings _s;

        // landmark groups: outer corner, inner corner, upper lid, lower lid, iris centre
        static readonly int[] EyeA = { 33, 133, 159, 145, 468 };
        static readonly int[] EyeB = { 263, 362, 386, 374, 473 };
        const int Forehead = 10, Chin = 152;

        static int Ix(string n) => Array.IndexOf(TrackingFrame.BlendNames, n);
        static readonly int jawOpen = Ix("jawOpen"), funnel = Ix("mouthFunnel"), pucker = Ix("mouthPucker"),
            smileL = Ix("mouthSmileLeft"), smileR = Ix("mouthSmileRight"),
            stretchL = Ix("mouthStretchLeft"), stretchR = Ix("mouthStretchRight"),
            frownL = Ix("mouthFrownLeft"), frownR = Ix("mouthFrownRight"),
            blinkLeft = Ix("eyeBlinkLeft"), blinkRight = Ix("eyeBlinkRight"),
            wideL = Ix("eyeWideLeft"), wideR = Ix("eyeWideRight"),
            browDownL = Ix("browDownLeft"), browDownR = Ix("browDownRight"), browInner = Ix("browInnerUp"),
            browOuterL = Ix("browOuterUpLeft"), browOuterR = Ix("browOuterUpRight"),
            sneerL = Ix("noseSneerLeft"), sneerR = Ix("noseSneerRight"), cheekL = Ix("cheekSquintLeft"), cheekR = Ix("cheekSquintRight");

        const int N = 24;
        readonly OneEuroFilter[] _c = new OneEuroFilter[N];
        readonly OneEuroQuaternion _headF = new OneEuroQuaternion();
        float _yaw, _pitch;

        public FaceSolver(AppSettings s)
        {
            _s = s;
            for (int i = 0; i < N; i++) _c[i] = new OneEuroFilter();
        }

        float Fl(int c, float v, float dt, float k = 1f) => _c[c].Filter(v, dt, _s.faceMinCutoff * k, _s.faceBeta * k);

        public void Relax(float dt)
        {
            State.Valid = false;
            float d = Mathf.Exp(-6f * dt);
            State.BlinkL *= d; State.BlinkR *= d;
            State.Aa *= d; State.Ih *= d; State.Ou *= d; State.Ee *= d; State.Oh *= d;
            State.Happy *= d; State.Angry *= d; State.Sad *= d; State.Surprised *= d;
            State.BrowAngry *= d; State.BrowFun *= d; State.BrowJoy *= d; State.BrowSorrow *= d; State.BrowSurprised *= d;
            State.MthJoy *= d; State.GazeYaw *= d; State.GazePitch *= d;
        }

        public void Solve(TrackingFrame f, float dt)
        {
            if (f == null || !f.faceValid || !_s.trackFace) { Relax(dt); return; }
            dt = Mathf.Clamp(dt, 0.005f, 0.25f);
            State.Valid = true;
            bool mirror = _s.mirror;
            float W = f.imgW, H = f.imgH;

            // ---------------- head orientation from the mesh ----------------
            Vector3 Raw(int i) { var p = f.face[i]; return new Vector3(p.x * W, p.y * H, p.z * W); }
            Vector3 User(int i) { var r = Raw(i); return new Vector3(-r.x, -r.y, -r.z); }

            // In the unmirrored camera image the performer's RIGHT eye is on the image's left (smaller x).
            bool aIsUserRight = (Raw(EyeA[0]).x + Raw(EyeA[1]).x) < (Raw(EyeB[0]).x + Raw(EyeB[1]).x);
            int[] rightEye = aIsUserRight ? EyeA : EyeB;
            int[] leftEye = aIsUserRight ? EyeB : EyeA;

            Vector3 rPt = User(rightEye[0]), lPt = User(leftEye[0]);
            Vector3 fore = User(Forehead), chin = User(Chin);
            if (mirror)
            {
                Vector3 r2 = SolverMath.Mirror(lPt), l2 = SolverMath.Mirror(rPt);
                rPt = r2; lPt = l2;
                fore = SolverMath.Mirror(fore); chin = SolverMath.Mirror(chin);
            }
            Quaternion head = SolverMath.Clamp(SolverMath.FrameFrom(rPt - lPt, fore - chin), 75f);
            State.HeadLocal = _headF.Filter(head, dt, _s.faceMinCutoff, _s.faceBeta);

            // ---------------- blink ----------------
            float bUserL = Mathf.InverseLerp(0.15f, 0.60f, f.blend[blinkLeft]);
            float bUserR = Mathf.InverseLerp(0.15f, 0.60f, f.blend[blinkRight]);
            float bL = mirror ? bUserR : bUserL;      // avatar's left eye
            float bR = mirror ? bUserL : bUserR;
            if (_s.swapEyes) { float t = bL; bL = bR; bR = t; }
            State.BlinkL = Fl(0, bL, dt, 4f);
            State.BlinkR = Fl(1, bR, dt, 4f);

            // ---------------- mouth visemes (heuristic mapping, tuned for VRoid's A/I/U/E/O) ----------------
            float jaw = f.blend[jawOpen], fun = f.blend[funnel], puck = f.blend[pucker];
            float smile = (f.blend[smileL] + f.blend[smileR]) * 0.5f;
            float stretch = (f.blend[stretchL] + f.blend[stretchR]) * 0.5f;
            float open = Mathf.Clamp01(jaw * 1.5f * _s.mouthGain);
            float round = Mathf.Max(fun, puck);

            float aa = open * (1f - 0.8f * round) * (1f - 0.4f * smile);
            float oh = Mathf.Clamp01(fun * 1.6f * _s.mouthGain) * Mathf.Lerp(0.5f, 1f, open);
            float ou = Mathf.Clamp01(puck * 1.6f * _s.mouthGain) * Mathf.Lerp(0.5f, 1f, open);
            float ee = Mathf.Clamp01(smile * 1.2f + stretch * 1.2f) * (1f - 0.5f * open) * (1f - round);
            float ih = Mathf.Clamp01(stretch * 1.5f - smile * 0.3f) * Mathf.Lerp(0.4f, 1f, open) * (1f - round);
            float sum = aa + ih + ou + ee + oh;
            if (sum > 1f) { aa /= sum; ih /= sum; ou /= sum; ee /= sum; oh /= sum; }
            State.Aa = Fl(2, aa, dt, 2f); State.Ih = Fl(3, ih, dt, 2f); State.Ou = Fl(4, ou, dt, 2f);
            State.Ee = Fl(5, ee, dt, 2f); State.Oh = Fl(6, oh, dt, 2f);

            // ---------------- brows / emotions ----------------
            float browDown = (f.blend[browDownL] + f.blend[browDownR]) * 0.5f;
            float browOuter = (f.blend[browOuterL] + f.blend[browOuterR]) * 0.5f;
            float inner = f.blend[browInner];
            float wide = (f.blend[wideL] + f.blend[wideR]) * 0.5f;
            float frown = (f.blend[frownL] + f.blend[frownR]) * 0.5f;
            float sneer = (f.blend[sneerL] + f.blend[sneerR]) * 0.5f;
            float cheek = (f.blend[cheekL] + f.blend[cheekR]) * 0.5f;
            float g = _s.browGain, e = _s.emotionStrength;

            State.BrowAngry = Fl(7, Mathf.Clamp01((browDown * 1.6f - inner * 0.5f) * g), dt);
            State.BrowSurprised = Fl(8, Mathf.Clamp01((browOuter * 1.6f + wide * 0.6f) * g), dt);
            State.BrowSorrow = Fl(9, Mathf.Clamp01((inner * 1.5f - browOuter) * g), dt);
            State.BrowJoy = Fl(10, Mathf.Clamp01(smile * 0.6f * g), dt);
            State.BrowFun = Fl(11, 0f, dt);
            State.MthJoy = Fl(12, Mathf.Clamp01((smile - 0.1f) * 1.5f), dt);

            State.Happy = Fl(13, Mathf.Clamp01((smile - 0.55f) * 3f + cheek * 0.2f) * e, dt);
            State.Surprised = Fl(14, Mathf.Clamp01((browOuter * 0.6f + wide * 0.8f + jaw * 0.5f - 0.6f) * 2.2f) * e, dt);
            State.Angry = Fl(15, Mathf.Clamp01((browDown + sneer * 0.5f - 0.5f) * 2.5f) * e, dt);
            State.Sad = Fl(16, Mathf.Clamp01((inner * 0.8f + frown - 0.55f) * 2.5f) * e, dt);

            // ---------------- gaze from the iris landmarks ----------------
            if (Mathf.Max(State.BlinkL, State.BlinkR) < 0.5f)
            {
                Vector2 o = (EyeOffset(f, EyeA) + EyeOffset(f, EyeB)) * 0.5f;   // image coords, +x right, +y down
                float yawUser = -o.x * _s.gazeGain;       // image-left = performer's right
                float pitchUp = -o.y * _s.gazeGain;
                if (mirror) yawUser = -yawUser;
                if (_s.invertGazeYaw) yawUser = -yawUser;
                if (_s.invertGazePitch) pitchUp = -pitchUp;
                _yaw = Fl(17, Mathf.Clamp(yawUser, -45f, 45f), dt);
                _pitch = Fl(18, Mathf.Clamp(pitchUp, -30f, 30f), dt);
            }
            State.GazeYaw = _yaw; State.GazePitch = _pitch;
        }

        static Vector2 EyeOffset(TrackingFrame f, int[] e)
        {
            Vector2 Px(int i) => new Vector2(f.face[i].x * f.imgW, f.face[i].y * f.imgH);
            Vector2 outer = Px(e[0]), inner = Px(e[1]), up = Px(e[2]), lo = Px(e[3]), iris = Px(e[4]);
            float w = Vector2.Distance(outer, inner);
            if (w < 1e-3f) return Vector2.zero;
            Vector2 c = (outer + inner) * 0.5f;
            return new Vector2((iris.x - c.x) / w, (iris.y - (up.y + lo.y) * 0.5f) / w);
        }
    }
}
