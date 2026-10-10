using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Networking;
using UniVRM10;

namespace SaintVessel
{
    /// <summary>Loads the VRM 1.0 avatar at runtime and drives it from tracking data.</summary>
    public sealed class AvatarController : MonoBehaviour
    {
        public string LoadStatus { get; private set; } = "Loading avatar...";
        public bool Ready => _rig != null;
        public Vector3 FacingWorld => _rig == null ? Vector3.back : _holder.rotation * _rig.ForwardRoot;

        AppSettings _s;
        TrackingService _tracking;
        EnvironmentController _env;
        Vrm10Instance _vrm;
        Transform _holder;   // scaled/positioned parent of the avatar (keeps camera/light unscaled)
        AvatarRig _rig;
        PoseSolver _pose;
        FaceSolver _face;

        readonly Dictionary<HumanBodyBones, Quaternion> _cur = new Dictionary<HumanBodyBones, Quaternion>();
        float _lastFrameT, _idleAccum, _lastDt = 1f / 30f, _lastArrival;
        float _nextBlink = 3f, _blinkT = -1f;

        // smoothed outputs
        float _bl, _br, _aa, _ih, _ou, _ee, _oh, _hp, _an, _sa, _su, _yaw, _pitch;
        readonly float[] _morph = new float[8];

        static readonly HumanBodyBones[] Order =
        {
            HumanBodyBones.Hips, HumanBodyBones.Spine, HumanBodyBones.Chest, HumanBodyBones.UpperChest,
            HumanBodyBones.LeftShoulder, HumanBodyBones.RightShoulder, HumanBodyBones.Neck, HumanBodyBones.Head,
            HumanBodyBones.LeftUpperArm, HumanBodyBones.LeftLowerArm, HumanBodyBones.LeftHand,
            HumanBodyBones.RightUpperArm, HumanBodyBones.RightLowerArm, HumanBodyBones.RightHand,
            HumanBodyBones.LeftUpperLeg, HumanBodyBones.LeftLowerLeg, HumanBodyBones.LeftFoot,
            HumanBodyBones.RightUpperLeg, HumanBodyBones.RightLowerLeg, HumanBodyBones.RightFoot,
        };

        // VRoid face morph targets driven directly (Saint.vrm exposes no custom VRM expressions for brows)
        static readonly string[] MorphNames =
        {
            "Fcl_BRW_Angry", "Fcl_BRW_Surprised", "Fcl_BRW_Sorrow", "Fcl_BRW_Joy", "Fcl_BRW_Fun", "Fcl_MTH_Joy"
        };
        readonly int[] _morphIdx = new int[MorphNames.Length];

        public void Init(AppSettings s, TrackingService tracking, EnvironmentController env)
        {
            _s = s; _tracking = tracking; _env = env;
            _holder = new GameObject("AvatarRoot").transform;
            _holder.SetParent(transform, false);
            Load();
        }

        // ------------------------------------------------------------------ loading

        async void Load()
        {
            try
            {
                byte[] bytes = await ReadModelBytes();
                LoadStatus = "Parsing VRM...";
                // UniVRM 0.125: (bytes, canLoadVrm0X, controlRigGenerationOption, showMeshes)
                _vrm = await Vrm10.LoadBytesAsync(bytes, false, ControlRigGenerationOption.Generate, true);
                if (_vrm == null) throw new Exception("VRM load returned null");

                _vrm.transform.SetParent(_holder, false);
                foreach (var r in _vrm.GetComponentsInChildren<SkinnedMeshRenderer>(true))
                    r.updateWhenOffscreen = true;

                // gaze is set manually from the iris landmarks
                foreach (var n in new[] { "SetYawPitch", "YawPitchValue" })
                    if (Enum.IsDefined(typeof(VRM10ObjectLookAt.LookAtTargetTypes), n))
                    {
                        _vrm.LookAtTargetType = (VRM10ObjectLookAt.LookAtTargetTypes)Enum.Parse(typeof(VRM10ObjectLookAt.LookAtTargetTypes), n);
                        break;
                    }

                _rig = new AvatarRig(_vrm);
                _pose = new PoseSolver(_rig, _s);
                _face = new FaceSolver(_s);
                for (int i = 0; i < MorphNames.Length; i++)
                    _morphIdx[i] = _rig.FaceMesh != null ? _rig.FaceMesh.sharedMesh.GetBlendShapeIndex(MorphNames[i]) : -1;
                LoadStatus = "Ready";
            }
            catch (Exception e)
            {
                LoadStatus = "Avatar load failed: " + e.Message;
                Debug.LogException(e);
            }
        }

        async Task<byte[]> ReadModelBytes()
        {
            // 1) any .vrm dropped into <persistentDataPath>/Models wins (adb push / file manager)
            string dir = Path.Combine(Application.persistentDataPath, "Models");
            if (Directory.Exists(dir))
            {
                var files = Directory.GetFiles(dir, "*.vrm");
                Array.Sort(files);
                if (files.Length > 0) { LoadStatus = "Loading " + Path.GetFileName(files[0]); return File.ReadAllBytes(files[0]); }
            }
            // 2) bundled Saint.vrm from StreamingAssets
            string path = Path.Combine(Application.streamingAssetsPath, "Saint.vrm");
            LoadStatus = "Loading Saint.vrm";
            if (Application.platform != RuntimePlatform.Android) return File.ReadAllBytes(path);
            using (var req = UnityWebRequest.Get(path))
            {
                var op = req.SendWebRequest();
                while (!op.isDone) await Task.Yield();
                if (req.result != UnityWebRequest.Result.Success) throw new IOException(req.error);
                return req.downloadHandler.data;
            }
        }

        // ------------------------------------------------------------------ per frame

        void Update()
        {
            if (_rig == null) return;
            float dt = Time.deltaTime;

            _holder.localScale = Vector3.one * _s.avatarScale;
            _vrm.transform.localRotation = Quaternion.Euler(0f, _s.avatarYaw, 0f);

            bool fresh = _tracking.ConsumeNew();
            if (fresh)
            {
                float arrival = Time.unscaledTime;
                _lastDt = Mathf.Clamp(arrival - _lastArrival, 0.008f, 0.25f);
                _lastArrival = arrival;
                _lastFrameT = arrival;
                _face.Solve(_tracking.Frame, _lastDt);
                _pose.Solve(_tracking.Frame, _lastDt, _face.State.Valid, _face.State.HeadLocal);
            }
            else if (Time.unscaledTime - _lastFrameT > 0.5f)
            {
                // tracking lost / camera off: relax to an idle pose
                _idleAccum += dt;
                if (_idleAccum >= 1f / 30f)
                {
                    _face.Relax(_idleAccum);
                    _pose.Solve(null, _idleAccum, false, Quaternion.identity);
                    _idleAccum = 0f;
                }
            }

            ApplyBones(dt);
            ApplyFace(dt);
            _env.Frame(_holder.position, FacingWorld);
        }

        void ApplyBones(float dt)
        {
            float a = 1f - Mathf.Exp(-_s.followSpeed * dt);
            Quaternion rootRot = _rig.Root.rotation;
            foreach (var id in Order)
            {
                if (!_rig.Bones.TryGetValue(id, out var b) || !_pose.Targets.TryGetValue(id, out var tgt)) continue;
                if (!_cur.TryGetValue(id, out var cur)) cur = tgt;
                cur = Quaternion.Slerp(cur, tgt, a);
                _cur[id] = cur;
                b.T.rotation = rootRot * cur;
            }
            ApplyFingers();
        }

        static readonly HumanBodyBones[][] Fingers =
        {
            new[] { HumanBodyBones.LeftIndexProximal, HumanBodyBones.LeftIndexIntermediate, HumanBodyBones.LeftIndexDistal },
            new[] { HumanBodyBones.LeftMiddleProximal, HumanBodyBones.LeftMiddleIntermediate, HumanBodyBones.LeftMiddleDistal },
            new[] { HumanBodyBones.LeftRingProximal, HumanBodyBones.LeftRingIntermediate, HumanBodyBones.LeftRingDistal },
            new[] { HumanBodyBones.LeftLittleProximal, HumanBodyBones.LeftLittleIntermediate, HumanBodyBones.LeftLittleDistal },
            new[] { HumanBodyBones.LeftThumbProximal, HumanBodyBones.LeftThumbIntermediate, HumanBodyBones.LeftThumbDistal },
            new[] { HumanBodyBones.RightIndexProximal, HumanBodyBones.RightIndexIntermediate, HumanBodyBones.RightIndexDistal },
            new[] { HumanBodyBones.RightMiddleProximal, HumanBodyBones.RightMiddleIntermediate, HumanBodyBones.RightMiddleDistal },
            new[] { HumanBodyBones.RightRingProximal, HumanBodyBones.RightRingIntermediate, HumanBodyBones.RightRingDistal },
            new[] { HumanBodyBones.RightLittleProximal, HumanBodyBones.RightLittleIntermediate, HumanBodyBones.RightLittleDistal },
            new[] { HumanBodyBones.RightThumbProximal, HumanBodyBones.RightThumbIntermediate, HumanBodyBones.RightThumbDistal },
        };

        /// <summary>Relaxed finger curl (the pose model does not track fingers). Rest frames equal root frame in the control rig.</summary>
        void ApplyFingers()
        {
            float rad = _s.fingerCurlDeg * Mathf.Deg2Rad;
            for (int f = 0; f < Fingers.Length; f++)
            {
                float k = (f == 4 || f == 9) ? 0.5f : 1f;   // thumbs curl less
                foreach (var id in Fingers[f])
                {
                    if (!_rig.Bones.TryGetValue(id, out var b) || !b.HasDir) continue;
                    Vector3 to = Vector3.RotateTowards(b.RestDir, Vector3.down, rad * k, 0f);
                    Quaternion delta = Quaternion.FromToRotation(b.RestDir, to);
                    b.T.localRotation = Quaternion.Inverse(b.RestRot) * delta * b.RestRot;
                }
            }
        }

        static void Sm(ref float cur, float target, float a) => cur = Mathf.Lerp(cur, target, a);

        void ApplyFace(float dt)
        {
            var st = _face.State;
            float a = 1f - Mathf.Exp(-(_s.followSpeed * 1.6f) * dt);

            float blinkL = st.BlinkL, blinkR = st.BlinkR;
            if (!st.Valid && _s.idleBlink)
            {
                _nextBlink -= dt;
                if (_nextBlink <= 0f) { _blinkT = 0f; _nextBlink = UnityEngine.Random.Range(2.5f, 5.5f); }
                if (_blinkT >= 0f)
                {
                    _blinkT += dt;
                    float v = Mathf.Sin(Mathf.Clamp01(_blinkT / 0.16f) * Mathf.PI);
                    blinkL = blinkR = v;
                    if (_blinkT > 0.16f) _blinkT = -1f;
                }
            }

            Sm(ref _bl, blinkL, Mathf.Max(a, 0.6f)); Sm(ref _br, blinkR, Mathf.Max(a, 0.6f));
            Sm(ref _aa, st.Aa, a); Sm(ref _ih, st.Ih, a); Sm(ref _ou, st.Ou, a); Sm(ref _ee, st.Ee, a); Sm(ref _oh, st.Oh, a);
            Sm(ref _hp, st.Happy, a); Sm(ref _an, st.Angry, a); Sm(ref _sa, st.Sad, a); Sm(ref _su, st.Surprised, a);
            Sm(ref _yaw, st.GazeYaw, a); Sm(ref _pitch, st.GazePitch, a);

            var ex = _vrm.Runtime.Expression;
            ex.SetWeight(ExpressionKey.BlinkLeft, _bl);
            ex.SetWeight(ExpressionKey.BlinkRight, _br);
            ex.SetWeight(ExpressionKey.Aa, _aa);
            ex.SetWeight(ExpressionKey.Ih, _ih);
            ex.SetWeight(ExpressionKey.Ou, _ou);
            ex.SetWeight(ExpressionKey.Ee, _ee);
            ex.SetWeight(ExpressionKey.Oh, _oh);
            ex.SetWeight(ExpressionKey.Happy, _hp);
            ex.SetWeight(ExpressionKey.Angry, _an);
            ex.SetWeight(ExpressionKey.Sad, _sa);
            ex.SetWeight(ExpressionKey.Surprised, _su);

            _vrm.Runtime.LookAt.SetYawPitchManually(_yaw, _pitch);

            // direct morph targets (brows + smile shape without closing the eyes)
            if (_rig.FaceMesh != null)
            {
                float[] t = { st.BrowAngry, st.BrowSurprised, st.BrowSorrow, st.BrowJoy, st.BrowFun, st.MthJoy };
                for (int i = 0; i < t.Length; i++)
                {
                    Sm(ref _morph[i], t[i], a);
                    if (_morphIdx[i] >= 0) _rig.FaceMesh.SetBlendShapeWeight(_morphIdx[i], _morph[i] * 100f);
                }
            }
        }
    }
}
