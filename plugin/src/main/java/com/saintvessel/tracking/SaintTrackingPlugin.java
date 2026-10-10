package com.saintvessel.tracking;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Matrix;
import android.os.SystemClock;
import android.util.Log;
import android.util.Size;

import androidx.annotation.NonNull;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleOwner;
import androidx.lifecycle.LifecycleRegistry;

import com.google.common.util.concurrent.ListenableFuture;
import com.google.mediapipe.framework.image.BitmapImageBuilder;
import com.google.mediapipe.framework.image.MPImage;
import com.google.mediapipe.tasks.components.containers.Category;
import com.google.mediapipe.tasks.components.containers.Landmark;
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark;
import com.google.mediapipe.tasks.core.BaseOptions;
import com.google.mediapipe.tasks.core.Delegate;
import com.google.mediapipe.tasks.vision.core.RunningMode;
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker;
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Godot plugin "SaintTracking".
 * Camera (CameraX) -> MediaPipe PoseLandmarker + FaceLandmarker -> one flat float[] packet that GDScript polls.
 *
 * Packet layout (must match scripts/tracking_frame.gd):
 *   [0] version (1)  [1] poseSeq  [2] faceSeq  [3] poseValid  [4] faceValid
 *   [5] imageWidth (after rotation)  [6] imageHeight  [7] reserved
 *   then 33 * (x,y,z,visibility)  pose WORLD landmarks (meters, hip-centred; x right / y down / z away from camera)
 *   then 478 * (x,y,z)            face mesh, normalized image coords (incl. iris)
 *   then 52                       ARKit-style face blendshapes (order = BLEND_NAMES)
 *
 * The frame given to MediaPipe is NOT mirrored (unless flip is requested), so left/right are anatomical.
 */
public class SaintTrackingPlugin extends GodotPlugin {
    private static final String TAG = "SaintTracking";

    public static final int POSE_N = 33, FACE_N = 478, BLEND_N = 52, HEADER = 8;
    public static final int PACKET = HEADER + POSE_N * 4 + FACE_N * 3 + BLEND_N;

    private static final String POSE_MODEL = "pose_landmarker.task";
    private static final String FACE_MODEL = "face_landmarker.task";

    private static final String[] BLEND_NAMES = {
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
    private static final Map<String, Integer> BLEND_INDEX = new HashMap<>();
    static {
        for (int i = 0; i < BLEND_NAMES.length; i++) BLEND_INDEX.put(BLEND_NAMES[i], i);
    }

    /** Minimal LifecycleOwner so CameraX can run inside Godot's plain Activity. */
    private static final class Owner implements LifecycleOwner {
        final LifecycleRegistry registry = new LifecycleRegistry(this);
        @NonNull @Override public Lifecycle getLifecycle() { return registry; }
    }

    private final Object lock = new Object();
    private final float[] packet = new float[PACKET];
    private final Owner owner = new Owner();

    private int poseSeq, faceSeq, sentPoseSeq = -1, sentFaceSeq = -1;
    private boolean poseValid, faceValid;
    private int imgW, imgH;
    private String status = "idle";

    private ProcessCameraProvider provider;
    private ExecutorService analysisExecutor;
    private PoseLandmarker pose;
    private FaceLandmarker face;
    private boolean useFront = true, useGpu = false;
    private volatile boolean flipHorizontal = false;
    private long lastTs = 0;

    public SaintTrackingPlugin(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "SaintTracking";
    }

    // ---------------------------------------------------------------- API called from GDScript

    @UsedByGodot
    public void start(final boolean front, final boolean flip, final boolean gpu) {
        final Activity activity = getActivity();
        if (activity == null) { setStatus("error: no activity"); return; }
        activity.runOnUiThread(new Runnable() {
            @Override public void run() {
                try {
                    stopInternal();
                    useFront = front;
                    flipHorizontal = flip;
                    useGpu = gpu;
                    setStatus("starting");
                    createLandmarkers(activity);
                    bindCamera(activity);
                } catch (Throwable t) {
                    Log.e(TAG, "start failed", t);
                    setStatus("error: " + t);
                }
            }
        });
    }

    @UsedByGodot
    public void stop() {
        Activity activity = getActivity();
        if (activity == null) return;
        activity.runOnUiThread(new Runnable() {
            @Override public void run() { stopInternal(); }
        });
    }

    @UsedByGodot
    public void setFlip(boolean flip) { flipHorizontal = flip; }

    @UsedByGodot
    public String getStatus() { synchronized (lock) { return status; } }

    /** Returns a fresh packet if anything changed since the last call, otherwise an empty array. */
    @UsedByGodot
    public float[] poll() {
        synchronized (lock) {
            if (poseSeq == sentPoseSeq && faceSeq == sentFaceSeq) return new float[0];
            sentPoseSeq = poseSeq;
            sentFaceSeq = faceSeq;
            packet[0] = 1f;
            packet[1] = poseSeq & 0xFFFFFF;
            packet[2] = faceSeq & 0xFFFFFF;
            packet[3] = poseValid ? 1f : 0f;
            packet[4] = faceValid ? 1f : 0f;
            packet[5] = imgW;
            packet[6] = imgH;
            return packet.clone();
        }
    }

    private void setStatus(String s) { synchronized (lock) { status = s; } }

    // ---------------------------------------------------------------- setup

    private void createLandmarkers(Activity activity) {
        closeLandmarkers();
        Delegate d = useGpu ? Delegate.GPU : Delegate.CPU;
        try {
            pose = buildPose(activity, d);
            face = buildFace(activity, d);
        } catch (RuntimeException e) {
            if (d == Delegate.GPU) {
                Log.w(TAG, "GPU delegate failed, falling back to CPU", e);
                closeLandmarkers();
                pose = buildPose(activity, Delegate.CPU);
                face = buildFace(activity, Delegate.CPU);
            } else {
                throw e;
            }
        }
    }

    private PoseLandmarker buildPose(Activity activity, Delegate d) {
        BaseOptions base = BaseOptions.builder().setModelAssetPath(POSE_MODEL).setDelegate(d).build();
        PoseLandmarker.PoseLandmarkerOptions o = PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(base)
                .setRunningMode(RunningMode.LIVE_STREAM)
                .setNumPoses(1)
                .setMinPoseDetectionConfidence(0.5f)
                .setMinPosePresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setResultListener(this::onPose)
                .setErrorListener(e -> Log.e(TAG, "pose error", e))
                .build();
        return PoseLandmarker.createFromOptions(activity.getApplicationContext(), o);
    }

    private FaceLandmarker buildFace(Activity activity, Delegate d) {
        BaseOptions base = BaseOptions.builder().setModelAssetPath(FACE_MODEL).setDelegate(d).build();
        FaceLandmarker.FaceLandmarkerOptions o = FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(base)
                .setRunningMode(RunningMode.LIVE_STREAM)
                .setNumFaces(1)
                .setOutputFaceBlendshapes(true)
                .setMinFaceDetectionConfidence(0.5f)
                .setMinFacePresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setResultListener(this::onFace)
                .setErrorListener(e -> Log.e(TAG, "face error", e))
                .build();
        return FaceLandmarker.createFromOptions(activity.getApplicationContext(), o);
    }

    private void bindCamera(final Activity activity) {
        final ListenableFuture<ProcessCameraProvider> future = ProcessCameraProvider.getInstance(activity);
        future.addListener(new Runnable() {
            @Override public void run() {
                try {
                    provider = future.get();
                    provider.unbindAll();

                    analysisExecutor = Executors.newSingleThreadExecutor();
                    ImageAnalysis analysis = new ImageAnalysis.Builder()
                            .setTargetResolution(new Size(640, 480))
                            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                            .build();
                    analysis.setAnalyzer(analysisExecutor, new ImageAnalysis.Analyzer() {
                        @Override public void analyze(@NonNull ImageProxy image) { onImage(image); }
                    });

                    CameraSelector selector = useFront
                            ? CameraSelector.DEFAULT_FRONT_CAMERA : CameraSelector.DEFAULT_BACK_CAMERA;
                    owner.registry.setCurrentState(Lifecycle.State.STARTED);
                    provider.bindToLifecycle(owner, selector, analysis);
                    setStatus("running");
                } catch (Throwable t) {
                    Log.e(TAG, "camera bind failed", t);
                    setStatus("error: " + t);
                }
            }
        }, ContextCompat.getMainExecutor(activity));
    }

    private void stopInternal() {
        try {
            if (provider != null) provider.unbindAll();
            owner.registry.setCurrentState(Lifecycle.State.CREATED);
        } catch (Throwable t) {
            Log.w(TAG, "stop", t);
        }
        if (analysisExecutor != null) { analysisExecutor.shutdown(); analysisExecutor = null; }
        closeLandmarkers();
        synchronized (lock) {
            poseValid = false; faceValid = false; poseSeq++; faceSeq++;
            status = "stopped";
        }
    }

    private void closeLandmarkers() {
        try { if (pose != null) pose.close(); } catch (Throwable ignored) {}
        try { if (face != null) face.close(); } catch (Throwable ignored) {}
        pose = null; face = null;
    }

    // ---------------------------------------------------------------- per frame

    private void onImage(ImageProxy image) {
        try {
            PoseLandmarker p = pose;
            FaceLandmarker f = face;
            if (p == null || f == null) return;

            long ts = SystemClock.uptimeMillis();
            if (ts <= lastTs) ts = lastTs + 1;
            lastTs = ts;

            int w = image.getWidth(), h = image.getHeight();
            Bitmap bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            ImageProxy.PlaneProxy plane = image.getPlanes()[0];
            ByteBuffer buf = plane.getBuffer();
            int rowStride = plane.getRowStride();
            if (rowStride == w * 4) {
                bmp.copyPixelsFromBuffer(buf);
            } else {
                ByteBuffer packed = ByteBuffer.allocateDirect(w * 4 * h);
                byte[] row = new byte[w * 4];
                for (int y = 0; y < h; y++) {
                    buf.position(y * rowStride);
                    buf.get(row, 0, w * 4);
                    packed.put(row);
                }
                packed.rewind();
                bmp.copyPixelsFromBuffer(packed);
            }

            Matrix m = new Matrix();
            m.postRotate(image.getImageInfo().getRotationDegrees());
            if (flipHorizontal) m.postScale(-1f, 1f);
            Bitmap oriented = Bitmap.createBitmap(bmp, 0, 0, w, h, m, true);
            if (oriented != bmp) bmp.recycle();

            synchronized (lock) { imgW = oriented.getWidth(); imgH = oriented.getHeight(); }

            MPImage mp = new BitmapImageBuilder(oriented).build();
            f.detectAsync(mp, ts);
            p.detectAsync(mp, ts);
        } catch (Throwable t) {
            Log.e(TAG, "frame", t);
        } finally {
            image.close();
        }
    }

    private void onPose(PoseLandmarkerResult r, MPImage input) {
        synchronized (lock) {
            boolean ok = r != null && !r.worldLandmarks().isEmpty() && !r.landmarks().isEmpty()
                    && r.worldLandmarks().get(0).size() >= POSE_N && r.landmarks().get(0).size() >= POSE_N;
            poseValid = ok;
            if (ok) {
                List<Landmark> world = r.worldLandmarks().get(0);
                List<NormalizedLandmark> img = r.landmarks().get(0);
                for (int i = 0; i < POSE_N; i++) {
                    int o = HEADER + i * 4;
                    Landmark l = world.get(i);
                    packet[o] = l.x();
                    packet[o + 1] = l.y();
                    packet[o + 2] = l.z();
                    packet[o + 3] = img.get(i).visibility().orElse(1f);
                }
            }
            poseSeq++;
        }
    }

    private void onFace(FaceLandmarkerResult r, MPImage input) {
        synchronized (lock) {
            boolean ok = r != null && !r.faceLandmarks().isEmpty() && r.faceLandmarks().get(0).size() >= FACE_N;
            faceValid = ok;
            if (ok) {
                int base = HEADER + POSE_N * 4;
                List<NormalizedLandmark> lm = r.faceLandmarks().get(0);
                for (int i = 0; i < FACE_N; i++) {
                    NormalizedLandmark l = lm.get(i);
                    packet[base + i * 3] = l.x();
                    packet[base + i * 3 + 1] = l.y();
                    packet[base + i * 3 + 2] = l.z();
                }
                int bBase = base + FACE_N * 3;
                for (int i = 0; i < BLEND_N; i++) packet[bBase + i] = 0f;
                if (r.faceBlendshapes().isPresent() && !r.faceBlendshapes().get().isEmpty()) {
                    for (Category c : r.faceBlendshapes().get().get(0)) {
                        Integer idx = BLEND_INDEX.get(c.categoryName());
                        if (idx != null) packet[bBase + idx] = c.score();
                    }
                }
            }
            faceSeq++;
        }
    }
}
