using System;
using UnityEngine;

namespace SaintVessel
{
    /// <summary>
    /// Decoded tracking packet. Layout must match TrackingBridge.java.
    /// Pose is in MediaPipe WORLD space: meters, hip-centred, x = image right, y = image down, z = away from camera.
    /// Face mesh is in normalized image coords (x,y in 0..1, z same scale as x, smaller = closer).
    /// </summary>
    public sealed class TrackingFrame
    {
        public const int PoseCount = 33, FaceCount = 478, BlendCount = 52, Header = 8;
        public const int PacketSize = Header + PoseCount * 4 + FaceCount * 3 + BlendCount;

        public static readonly string[] BlendNames =
        {
            "_neutral", "browDownLeft", "browDownRight", "browInnerUp", "browOuterUpLeft", "browOuterUpRight",
            "cheekPuff", "cheekSquintLeft", "cheekSquintRight", "eyeBlinkLeft", "eyeBlinkRight",
            "eyeLookDownLeft", "eyeLookDownRight", "eyeLookInLeft", "eyeLookInRight", "eyeLookOutLeft",
            "eyeLookOutRight", "eyeLookUpLeft", "eyeLookUpRight", "eyeSquintLeft", "eyeSquintRight",
            "eyeWideLeft", "eyeWideRight", "jawForward", "jawLeft", "jawOpen", "jawRight", "mouthClose",
            "mouthDimpleLeft", "mouthDimpleRight", "mouthFrownLeft", "mouthFrownRight", "mouthFunnel",
            "mouthLeft", "mouthLowerDownLeft", "mouthLowerDownRight", "mouthPressLeft", "mouthPressRight",
            "mouthPucker", "mouthRight", "mouthRollLower", "mouthRollUpper", "mouthShrugLower",
            "mouthShrugUpper", "mouthSmileLeft", "mouthSmileRight", "mouthStretchLeft", "mouthStretchRight",
            "mouthUpperUpLeft", "mouthUpperUpRight", "noseSneerLeft", "noseSneerRight"
        };

        public bool poseValid, faceValid;
        public float imgW = 480f, imgH = 640f;
        public readonly Vector3[] poseWorld = new Vector3[PoseCount];
        public readonly float[] poseVis = new float[PoseCount];
        public readonly Vector3[] face = new Vector3[FaceCount];
        public readonly float[] blend = new float[BlendCount];

        public bool Parse(float[] d)
        {
            if (d == null || d.Length != PacketSize) return false;
            poseValid = d[3] > 0.5f;
            faceValid = d[4] > 0.5f;
            imgW = Mathf.Max(1f, d[5]);
            imgH = Mathf.Max(1f, d[6]);

            int o = Header;
            for (int i = 0; i < PoseCount; i++, o += 4)
            {
                poseWorld[i] = new Vector3(d[o], d[o + 1], d[o + 2]);
                poseVis[i] = d[o + 3];
            }
            for (int i = 0; i < FaceCount; i++, o += 3)
                face[i] = new Vector3(d[o], d[o + 1], d[o + 2]);
            Array.Copy(d, o, blend, 0, BlendCount);
            return true;
        }
    }
}
