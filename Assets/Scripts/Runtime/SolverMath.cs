using UnityEngine;

namespace SaintVessel
{
    public static class SolverMath
    {
        /// <summary>Reflect across the avatar's own left/right plane (x axis of the avatar-local frame).</summary>
        public static Vector3 Mirror(Vector3 v) => new Vector3(-v.x, v.y, v.z);

        /// <summary>
        /// Builds an orientation from a "right" and "up" hint (avatar-local frame: x right, y up, z forward;
        /// Unity is left-handed so forward = right x up).
        /// </summary>
        public static Quaternion FrameFrom(Vector3 right, Vector3 up)
        {
            if (up.sqrMagnitude < 1e-8f) return Quaternion.identity;
            up.Normalize();
            right -= Vector3.Dot(right, up) * up;
            if (right.sqrMagnitude < 1e-8f) return Quaternion.identity;
            right.Normalize();
            Vector3 fwd = Vector3.Cross(right, up);
            return Quaternion.LookRotation(fwd, up);
        }

        public static Quaternion Clamp(Quaternion q, float maxDeg)
            => Quaternion.RotateTowards(Quaternion.identity, q, maxDeg);

        /// <summary>MediaPipe pose index of the opposite side (nose stays; eyes are not used).</summary>
        public static int SwapSide(int i) => i < 7 ? i : ((i & 1) == 1 ? i + 1 : i - 1);
    }
}
