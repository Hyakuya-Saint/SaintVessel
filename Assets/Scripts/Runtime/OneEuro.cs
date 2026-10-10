using UnityEngine;

namespace SaintVessel
{
    /// <summary>One Euro filter (Casiez et al.): strong smoothing when still, low lag when moving fast.</summary>
    public sealed class OneEuroFilter
    {
        float _x, _dx;
        bool _init;
        public float Last => _x;

        public void Reset(float value) { _x = value; _dx = 0f; _init = true; }

        public float Filter(float v, float dt, float minCutoff, float beta)
        {
            dt = Mathf.Max(dt, 1e-4f);
            if (!_init) { Reset(v); return v; }
            float dx = (v - _x) / dt;
            _dx = Mathf.Lerp(_dx, dx, Alpha(1f, dt));
            float cutoff = minCutoff + beta * Mathf.Abs(_dx);
            _x = Mathf.Lerp(_x, v, Alpha(cutoff, dt));
            return _x;
        }

        public static float Alpha(float cutoff, float dt)
        {
            float tau = 1f / (2f * Mathf.PI * Mathf.Max(cutoff, 1e-3f));
            return 1f / (1f + tau / dt);
        }
    }

    public sealed class OneEuroVector3
    {
        readonly OneEuroFilter _x = new OneEuroFilter(), _y = new OneEuroFilter(), _z = new OneEuroFilter();
        public Vector3 Last => new Vector3(_x.Last, _y.Last, _z.Last);

        public void Reset(Vector3 v) { _x.Reset(v.x); _y.Reset(v.y); _z.Reset(v.z); }

        public Vector3 Filter(Vector3 v, float dt, float minCutoff, float beta)
            => new Vector3(_x.Filter(v.x, dt, minCutoff, beta),
                           _y.Filter(v.y, dt, minCutoff, beta),
                           _z.Filter(v.z, dt, minCutoff, beta));
    }

    /// <summary>Angular-speed driven smoothing for rotations.</summary>
    public sealed class OneEuroQuaternion
    {
        Quaternion _q = Quaternion.identity;
        float _speed;
        bool _init;
        public Quaternion Last => _q;

        public Quaternion Filter(Quaternion q, float dt, float minCutoff, float beta)
        {
            dt = Mathf.Max(dt, 1e-4f);
            if (!_init) { _init = true; _q = q; return q; }
            float speed = Quaternion.Angle(_q, q) * Mathf.Deg2Rad / dt;
            _speed = Mathf.Lerp(_speed, speed, OneEuroFilter.Alpha(1f, dt));
            float cutoff = minCutoff + beta * _speed;
            _q = Quaternion.Slerp(_q, q, OneEuroFilter.Alpha(cutoff, dt));
            return _q;
        }
    }
}
