using System.Collections.Generic;
using UnityEngine;

namespace SaintVessel
{
    /// <summary>
    /// MediaPipe pose (world landmarks) -> target rotations (root space) for the VRM normalized humanoid.
    ///
    /// Conventions
    ///  * Landmarks are converted to the performer's frame (x = their right, y = up, z = facing direction):
    ///        user = (-mp.x, -mp.y, -mp.z)         (MediaPipe: x right, y down, z away from camera, unmirrored image)
    ///  * Mirror mode reflects x and swaps left/right landmarks, so the avatar behaves like a mirror.
    ///    Non-mirror mode keeps anatomy: avatar's right arm follows the performer's right arm.
    ///  * Everything is then solved in the avatar-local frame (x right, y up, z forward) and mapped to root space
    ///    through AvatarRig.Frame, so the model's +Z/-Z facing in Unity never matters.
    ///  * Limbs are aimed with swing-only rotations from their rest direction (scale independent, no twist).
    ///    Torso/hips/head are solved from orthonormal frames so they get yaw, pitch and roll.
    /// </summary>
    public sealed class PoseSolver
    {
        enum Seg { LUpperArm, LLowerArm, LHand, RUpperArm, RLowerArm, RHand, LUpperLeg, LLowerLeg, LFoot, RUpperLeg, RLowerLeg, RFoot, Count }

        public readonly Dictionary<HumanBodyBones, Quaternion> Targets = new Dictionary<HumanBodyBones, Quaternion>();

        readonly AvatarRig _rig;
        readonly AppSettings _s;
        readonly OneEuroVector3[] _segF = new OneEuroVector3[(int)Seg.Count];
        readonly float[] _segW = new float[(int)Seg.Count];
        readonly OneEuroQuaternion _hipsF = new OneEuroQuaternion(), _shF = new OneEuroQuaternion();
        float _torsoW;

        TrackingFrame _f;
        bool _mirror;
        float _mc, _bt;

        public PoseSolver(AvatarRig rig, AppSettings s)
        {
            _rig = rig; _s = s;
            for (int i = 0; i < (int)Seg.Count; i++)
            {
                _segF[i] = new OneEuroVector3();
                _segF[i].Reset(IdleDir((Seg)i));
            }
        }

        static float Side(Seg s) => (s == Seg.LUpperArm || s == Seg.LLowerArm || s == Seg.LHand ||
                                     s == Seg.LUpperLeg || s == Seg.LLowerLeg || s == Seg.LFoot) ? -1f : 1f;

        /// <summary>Relaxed standing pose in avatar-local space (arms down, legs straight).</summary>
        static Vector3 IdleDir(Seg s)
        {
            float k = Side(s);
            switch (s)
            {
                case Seg.LUpperArm: case Seg.RUpperArm: return new Vector3(k * 0.18f, -0.98f, 0.05f).normalized;
                case Seg.LLowerArm: case Seg.RLowerArm:
                case Seg.LHand: case Seg.RHand: return new Vector3(k * 0.10f, -0.97f, 0.20f).normalized;
                case Seg.LUpperLeg: case Seg.RUpperLeg: return new Vector3(k * 0.02f, -1f, 0f).normalized;
                case Seg.LLowerLeg: case Seg.RLowerLeg: return new Vector3(k * 0.01f, -1f, 0.02f).normalized;
                default: return new Vector3(0f, -0.25f, 0.97f).normalized;   // feet
            }
        }

        // ---- landmark access in avatar-local space ------------------------------------------------

        int Idx(int i) => _mirror ? SolverMath.SwapSide(i) : i;
        bool V(int i) => _f.poseVis[Idx(i)] > 0.5f;

        Vector3 P(int i)
        {
            Vector3 w = _f.poseWorld[Idx(i)];
            var u = new Vector3(-w.x, -w.y, -w.z * _s.poseDepthScale);
            if (_mirror) u = SolverMath.Mirror(u);
            return u;
        }

        Vector3 Seg3(Seg id, bool ok, Vector3 measured, Vector3 idle, float dt)
        {
            int i = (int)id;
            if (ok && measured.sqrMagnitude > 1e-8f)
                _segF[i].Filter(measured.normalized, dt, _mc, _bt);
            _segW[i] = Mathf.MoveTowards(_segW[i], ok ? 1f : 0f, dt * 3f);
            Vector3 last = _segF[i].Last;
            if (last.sqrMagnitude < 1e-6f) last = idle;
            return Vector3.Slerp(idle.normalized, last.normalized, _segW[i]).normalized;
        }

        // ---- main entry ---------------------------------------------------------------------------

        /// <param name="f">latest frame or null for idle</param>
        /// <param name="headValid">face tracker produced a head rotation (avatar-local, absolute)</param>
        public void Solve(TrackingFrame f, float dt, bool headValid, Quaternion headLocal)
        {
            dt = Mathf.Clamp(dt, 0.005f, 0.25f);
            _f = f;
            _mirror = _s.mirror;
            _mc = _s.bodyMinCutoff; _bt = _s.bodyBeta;
            bool body = f != null && f.poseValid && _s.trackBody;

            // ---------------- torso ----------------
            bool shOk = body && V(11) && V(12);
            bool hipOk = shOk && V(23) && V(24);
            Quaternion hipsL = Quaternion.identity, shL = Quaternion.identity;
            if (shOk)
            {
                Vector3 shC = (P(11) + P(12)) * 0.5f;
                Vector3 up = hipOk ? (shC - (P(23) + P(24)) * 0.5f) : Vector3.up;
                shL = SolverMath.Clamp(SolverMath.FrameFrom(P(12) - P(11), up), 70f);
                if (hipOk)
                {
                    Vector3 hipsUp = Vector3.Slerp(Vector3.up, up.normalized, 0.35f);
                    hipsL = SolverMath.Clamp(SolverMath.FrameFrom(P(24) - P(23), hipsUp), 60f);
                }
                shL = _shF.Filter(shL, dt, _mc, _bt);
                hipsL = _hipsF.Filter(hipsL, dt, _mc, _bt);
            }
            _torsoW = Mathf.MoveTowards(_torsoW, shOk ? 1f : 0f, dt * 2.5f);
            Quaternion dH = Quaternion.Slerp(Quaternion.identity, hipsL, _torsoW);
            Quaternion dS = Quaternion.Slerp(Quaternion.identity, shL, _torsoW);

            Set(HumanBodyBones.Hips, dH);
            Set(HumanBodyBones.Spine, Quaternion.Slerp(dH, dS, 0.33f));
            Set(HumanBodyBones.Chest, Quaternion.Slerp(dH, dS, 0.66f));
            Set(HumanBodyBones.UpperChest, dS);

            // ---------------- head / neck ----------------
            Quaternion dHead = headValid ? headLocal : dS;
            Set(HumanBodyBones.Neck, Quaternion.Slerp(dS, dHead, 0.4f));
            Set(HumanBodyBones.Head, dHead);

            // ---------------- arms ----------------
            SolveArm(true, body, dt, dS);
            SolveArm(false, body, dt, dS);

            // ---------------- legs ----------------
            bool legs = body && _s.trackLegs;
            SolveLeg(true, legs, dt);
            SolveLeg(false, legs, dt);
        }

        void SolveArm(bool left, bool body, float dt, Quaternion dS)
        {
            int sh = left ? 11 : 12, el = sh + 2, wr = sh + 4, pk = sh + 6, ix = sh + 8;
            Seg sU = left ? Seg.LUpperArm : Seg.RUpperArm;
            Seg sL = left ? Seg.LLowerArm : Seg.RLowerArm;
            Seg sH = left ? Seg.LHand : Seg.RHand;

            bool okU = body && V(sh) && V(el);
            bool okL = okU && V(wr);
            bool okH = okL && V(pk) && V(ix);

            Vector3 dU = Seg3(sU, okU, okU ? P(el) - P(sh) : Vector3.zero, IdleDir(sU), dt);
            Vector3 dL = Seg3(sL, okL, okL ? P(wr) - P(el) : Vector3.zero, IdleDir(sL), dt);
            Vector3 hm = okH ? (P(pk) + P(ix)) * 0.5f - P(wr) : Vector3.zero;
            Vector3 dHand = Seg3(sH, okH, hm, dL, dt);

            var idU = left ? HumanBodyBones.LeftUpperArm : HumanBodyBones.RightUpperArm;
            var idL = left ? HumanBodyBones.LeftLowerArm : HumanBodyBones.RightLowerArm;
            var idH = left ? HumanBodyBones.LeftHand : HumanBodyBones.RightHand;
            Aim(idU, dU); Aim(idL, dL); Aim(idH, dHand);

            // Raise the shoulder a little when the arm goes above horizontal.
            var idS = left ? HumanBodyBones.LeftShoulder : HumanBodyBones.RightShoulder;
            if (_rig.Bones.TryGetValue(idS, out var sb) && sb.HasDir)
            {
                Quaternion baseRot = _rig.DeltaLocal(sb, dS);
                Vector3 restNow = _rig.Frame * dS * Quaternion.Inverse(_rig.Frame) * sb.RestDir;
                float w = Mathf.Clamp01(dU.y) * 0.35f;
                Vector3 liftDir = Vector3.Slerp(restNow, _rig.Frame * dU, w);
                Targets[idS] = Quaternion.FromToRotation(restNow, liftDir) * baseRot;
            }
        }

        void SolveLeg(bool left, bool legs, float dt)
        {
            int hp = left ? 23 : 24, kn = hp + 2, an = hp + 4, ft = hp + 8;
            Seg sU = left ? Seg.LUpperLeg : Seg.RUpperLeg;
            Seg sL = left ? Seg.LLowerLeg : Seg.RLowerLeg;
            Seg sF = left ? Seg.LFoot : Seg.RFoot;

            bool okU = legs && V(hp) && V(kn);
            bool okL = okU && V(an);
            bool okF = okL && V(ft);

            Vector3 dU = Seg3(sU, okU, okU ? P(kn) - P(hp) : Vector3.zero, IdleDir(sU), dt);
            Vector3 dL = Seg3(sL, okL, okL ? P(an) - P(kn) : Vector3.zero, IdleDir(sL), dt);
            Vector3 dF = Seg3(sF, okF, okF ? P(ft) - P(an) : Vector3.zero, IdleDir(sF), dt);

            Aim(left ? HumanBodyBones.LeftUpperLeg : HumanBodyBones.RightUpperLeg, dU);
            Aim(left ? HumanBodyBones.LeftLowerLeg : HumanBodyBones.RightLowerLeg, dL);
            Aim(left ? HumanBodyBones.LeftFoot : HumanBodyBones.RightFoot, dF);
        }

        void Aim(HumanBodyBones id, Vector3 dirLocal)
        {
            if (_rig.Bones.TryGetValue(id, out var b) && b.HasDir) Targets[id] = _rig.AimLocal(b, dirLocal);
        }

        void Set(HumanBodyBones id, Quaternion deltaLocal)
        {
            if (_rig.Bones.TryGetValue(id, out var b)) Targets[id] = _rig.DeltaLocal(b, deltaLocal);
        }
    }
}
