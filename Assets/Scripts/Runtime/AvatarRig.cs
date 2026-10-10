using System;
using System.Collections.Generic;
using UnityEngine;
using UniVRM10;

namespace SaintVessel
{
    /// <summary>
    /// Rest-pose data for the VRM 1.0 *normalized* humanoid (Vrm10 control rig).
    ///
    /// Why the control rig: VRoid exports bones with non-identity local rotations (Saint's hips carry ~7 deg of X
    /// rotation, shoulders and upper arms carry small Z/Y rotations...). Driving those raw bones with "T-pose
    /// identity" math drifts. UniVRM's control rig is a clone of the skeleton whose every bone has the same world
    /// rotation in T-pose, and UniVRM copies it back onto the real skeleton every LateUpdate (then runs spring bones).
    ///
    /// All data here is stored in ROOT space (relative to the avatar root), so moving/rotating/scaling the root
    /// afterwards never invalidates it.
    /// </summary>
    public sealed class AvatarRig
    {
        public sealed class Bone
        {
            public HumanBodyBones Id;
            public Transform T;
            public Quaternion RestRot;   // root space
            public Vector3 RestDir;      // root space, bone -> child direction in T-pose
            public bool HasDir;
        }

        public readonly Vrm10Instance Vrm;
        public readonly Transform Root;
        public readonly Dictionary<HumanBodyBones, Bone> Bones = new Dictionary<HumanBodyBones, Bone>();
        public Quaternion Frame = Quaternion.identity;   // avatar-local (x right, y up, z forward) -> root space
        public Vector3 ForwardRoot = Vector3.forward;    // direction the avatar faces, root space
        public SkinnedMeshRenderer FaceMesh;

        static readonly HumanBodyBones[] Used =
        {
            HumanBodyBones.Hips, HumanBodyBones.Spine, HumanBodyBones.Chest, HumanBodyBones.UpperChest,
            HumanBodyBones.Neck, HumanBodyBones.Head,
            HumanBodyBones.LeftShoulder, HumanBodyBones.RightShoulder,
            HumanBodyBones.LeftUpperArm, HumanBodyBones.LeftLowerArm, HumanBodyBones.LeftHand,
            HumanBodyBones.RightUpperArm, HumanBodyBones.RightLowerArm, HumanBodyBones.RightHand,
            HumanBodyBones.LeftUpperLeg, HumanBodyBones.LeftLowerLeg, HumanBodyBones.LeftFoot, HumanBodyBones.LeftToes,
            HumanBodyBones.RightUpperLeg, HumanBodyBones.RightLowerLeg, HumanBodyBones.RightFoot, HumanBodyBones.RightToes,
            HumanBodyBones.LeftThumbProximal, HumanBodyBones.LeftThumbIntermediate, HumanBodyBones.LeftThumbDistal,
            HumanBodyBones.LeftIndexProximal, HumanBodyBones.LeftIndexIntermediate, HumanBodyBones.LeftIndexDistal,
            HumanBodyBones.LeftMiddleProximal, HumanBodyBones.LeftMiddleIntermediate, HumanBodyBones.LeftMiddleDistal,
            HumanBodyBones.LeftRingProximal, HumanBodyBones.LeftRingIntermediate, HumanBodyBones.LeftRingDistal,
            HumanBodyBones.LeftLittleProximal, HumanBodyBones.LeftLittleIntermediate, HumanBodyBones.LeftLittleDistal,
            HumanBodyBones.RightThumbProximal, HumanBodyBones.RightThumbIntermediate, HumanBodyBones.RightThumbDistal,
            HumanBodyBones.RightIndexProximal, HumanBodyBones.RightIndexIntermediate, HumanBodyBones.RightIndexDistal,
            HumanBodyBones.RightMiddleProximal, HumanBodyBones.RightMiddleIntermediate, HumanBodyBones.RightMiddleDistal,
            HumanBodyBones.RightRingProximal, HumanBodyBones.RightRingIntermediate, HumanBodyBones.RightRingDistal,
            HumanBodyBones.RightLittleProximal, HumanBodyBones.RightLittleIntermediate, HumanBodyBones.RightLittleDistal,
        };

        // bone -> the bone whose position defines its rest direction (first existing candidate wins)
        static readonly Dictionary<HumanBodyBones, HumanBodyBones[]> Child = new Dictionary<HumanBodyBones, HumanBodyBones[]>
        {
            { HumanBodyBones.Spine, new[] { HumanBodyBones.Chest } },
            { HumanBodyBones.Chest, new[] { HumanBodyBones.UpperChest, HumanBodyBones.Neck } },
            { HumanBodyBones.UpperChest, new[] { HumanBodyBones.Neck } },
            { HumanBodyBones.Neck, new[] { HumanBodyBones.Head } },
            { HumanBodyBones.LeftShoulder, new[] { HumanBodyBones.LeftUpperArm } },
            { HumanBodyBones.RightShoulder, new[] { HumanBodyBones.RightUpperArm } },
            { HumanBodyBones.LeftUpperArm, new[] { HumanBodyBones.LeftLowerArm } },
            { HumanBodyBones.LeftLowerArm, new[] { HumanBodyBones.LeftHand } },
            { HumanBodyBones.LeftHand, new[] { HumanBodyBones.LeftMiddleProximal, HumanBodyBones.LeftIndexProximal } },
            { HumanBodyBones.RightUpperArm, new[] { HumanBodyBones.RightLowerArm } },
            { HumanBodyBones.RightLowerArm, new[] { HumanBodyBones.RightHand } },
            { HumanBodyBones.RightHand, new[] { HumanBodyBones.RightMiddleProximal, HumanBodyBones.RightIndexProximal } },
            { HumanBodyBones.LeftUpperLeg, new[] { HumanBodyBones.LeftLowerLeg } },
            { HumanBodyBones.LeftLowerLeg, new[] { HumanBodyBones.LeftFoot } },
            { HumanBodyBones.LeftFoot, new[] { HumanBodyBones.LeftToes } },
            { HumanBodyBones.RightUpperLeg, new[] { HumanBodyBones.RightLowerLeg } },
            { HumanBodyBones.RightLowerLeg, new[] { HumanBodyBones.RightFoot } },
            { HumanBodyBones.RightFoot, new[] { HumanBodyBones.RightToes } },
            { HumanBodyBones.LeftThumbProximal, new[] { HumanBodyBones.LeftThumbIntermediate } },
            { HumanBodyBones.LeftThumbIntermediate, new[] { HumanBodyBones.LeftThumbDistal } },
            { HumanBodyBones.LeftIndexProximal, new[] { HumanBodyBones.LeftIndexIntermediate } },
            { HumanBodyBones.LeftIndexIntermediate, new[] { HumanBodyBones.LeftIndexDistal } },
            { HumanBodyBones.LeftMiddleProximal, new[] { HumanBodyBones.LeftMiddleIntermediate } },
            { HumanBodyBones.LeftMiddleIntermediate, new[] { HumanBodyBones.LeftMiddleDistal } },
            { HumanBodyBones.LeftRingProximal, new[] { HumanBodyBones.LeftRingIntermediate } },
            { HumanBodyBones.LeftRingIntermediate, new[] { HumanBodyBones.LeftRingDistal } },
            { HumanBodyBones.LeftLittleProximal, new[] { HumanBodyBones.LeftLittleIntermediate } },
            { HumanBodyBones.LeftLittleIntermediate, new[] { HumanBodyBones.LeftLittleDistal } },
            { HumanBodyBones.RightThumbProximal, new[] { HumanBodyBones.RightThumbIntermediate } },
            { HumanBodyBones.RightThumbIntermediate, new[] { HumanBodyBones.RightThumbDistal } },
            { HumanBodyBones.RightIndexProximal, new[] { HumanBodyBones.RightIndexIntermediate } },
            { HumanBodyBones.RightIndexIntermediate, new[] { HumanBodyBones.RightIndexDistal } },
            { HumanBodyBones.RightMiddleProximal, new[] { HumanBodyBones.RightMiddleIntermediate } },
            { HumanBodyBones.RightMiddleIntermediate, new[] { HumanBodyBones.RightMiddleDistal } },
            { HumanBodyBones.RightRingProximal, new[] { HumanBodyBones.RightRingIntermediate } },
            { HumanBodyBones.RightRingIntermediate, new[] { HumanBodyBones.RightRingDistal } },
            { HumanBodyBones.RightLittleProximal, new[] { HumanBodyBones.RightLittleIntermediate } },
            { HumanBodyBones.RightLittleIntermediate, new[] { HumanBodyBones.RightLittleDistal } },
        };

        // distal bones have no child: reuse their parent's direction
        static readonly Dictionary<HumanBodyBones, HumanBodyBones> DistalParent = new Dictionary<HumanBodyBones, HumanBodyBones>
        {
            { HumanBodyBones.LeftThumbDistal, HumanBodyBones.LeftThumbIntermediate },
            { HumanBodyBones.LeftIndexDistal, HumanBodyBones.LeftIndexIntermediate },
            { HumanBodyBones.LeftMiddleDistal, HumanBodyBones.LeftMiddleIntermediate },
            { HumanBodyBones.LeftRingDistal, HumanBodyBones.LeftRingIntermediate },
            { HumanBodyBones.LeftLittleDistal, HumanBodyBones.LeftLittleIntermediate },
            { HumanBodyBones.RightThumbDistal, HumanBodyBones.RightThumbIntermediate },
            { HumanBodyBones.RightIndexDistal, HumanBodyBones.RightIndexIntermediate },
            { HumanBodyBones.RightMiddleDistal, HumanBodyBones.RightMiddleIntermediate },
            { HumanBodyBones.RightRingDistal, HumanBodyBones.RightRingIntermediate },
            { HumanBodyBones.RightLittleDistal, HumanBodyBones.RightLittleIntermediate },
        };

        public AvatarRig(Vrm10Instance vrm)
        {
            Vrm = vrm;
            Root = vrm.transform;
            var cr = vrm.Runtime.ControlRig;
            if (cr == null) throw new InvalidOperationException("VRM control rig was not generated.");

            Quaternion invRoot = Quaternion.Inverse(Root.rotation);
            foreach (var id in Used)
            {
                Transform t = null;
                try { t = cr.GetBoneTransform(id); } catch { /* optional bone not present */ }
                if (t == null) continue;
                Bones[id] = new Bone { Id = id, T = t, RestRot = invRoot * t.rotation };
            }

            foreach (var kv in Child)
            {
                if (!Bones.TryGetValue(kv.Key, out var b)) continue;
                foreach (var c in kv.Value)
                {
                    if (!Bones.TryGetValue(c, out var cb)) continue;
                    Vector3 d = Root.InverseTransformDirection(cb.T.position - b.T.position);
                    if (d.sqrMagnitude < 1e-10f) continue;
                    b.RestDir = d.normalized; b.HasDir = true; break;
                }
            }
            foreach (var kv in DistalParent)
                if (Bones.TryGetValue(kv.Key, out var b) && Bones.TryGetValue(kv.Value, out var p) && p.HasDir)
                { b.RestDir = p.RestDir; b.HasDir = true; }

            // Facing direction from the leg layout, so we never have to guess whether this model faces +Z or -Z.
            // (VRM 1.0 faces +Z in glTF; the Unity-side result depends on UniVRM's axis conversion.)
            if (Bones.TryGetValue(HumanBodyBones.LeftUpperLeg, out var ll) && Bones.TryGetValue(HumanBodyBones.RightUpperLeg, out var rl))
            {
                Vector3 right = Root.InverseTransformDirection(rl.T.position - ll.T.position);
                right.y = 0f;
                right.Normalize();
                ForwardRoot = Vector3.Cross(right, Vector3.up).normalized;   // Unity: forward = right x up
                Frame = Quaternion.LookRotation(ForwardRoot, Vector3.up);
            }

            foreach (var r in vrm.GetComponentsInChildren<SkinnedMeshRenderer>(true))
                if (r.sharedMesh != null && r.sharedMesh.blendShapeCount > 40) { FaceMesh = r; break; }
        }

        // ---- helpers used by the solvers ----------------------------------------------------------

        /// <summary>Rotation (root space) that aims the bone's rest direction at an avatar-local direction.</summary>
        public Quaternion AimLocal(Bone b, Vector3 dirLocal)
            => Quaternion.FromToRotation(b.RestDir, Frame * dirLocal) * b.RestRot;

        /// <summary>Rotation (root space) for a delta expressed in the avatar-local frame.</summary>
        public Quaternion DeltaLocal(Bone b, Quaternion deltaLocal)
            => Frame * deltaLocal * Quaternion.Inverse(Frame) * b.RestRot;
    }
}
