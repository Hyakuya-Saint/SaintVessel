using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace SaintVessel.Editor
{
    /// <summary>
    /// Headless / menu build entry point.
    /// CI calls: -executeMethod SaintVessel.Editor.BuildScript.BuildAndroid  (via game-ci/unity-builder buildMethod)
    /// Output:  build/Android/SaintVessel.apk
    /// </summary>
    public static class BuildScript
    {
        const string ScenePath = "Assets/Scenes/Main.unity";
        const string OutDir = "build/Android";
        const string ApkName = "SaintVessel.apk";
        const string VrmPath = "Assets/StreamingAssets/Saint.vrm";
        const string AnchorDir = "Assets/Resources/ShaderVariantAnchor";

        [MenuItem("Saint Vessel/Build Android APK")]
        public static void BuildAndroid()
        {
            try
            {
                Prepare();
                string output = Path.Combine(OutDir, ApkName);
                Directory.CreateDirectory(OutDir);

                var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
                {
                    scenes = new[] { ScenePath },
                    locationPathName = output,
                    target = BuildTarget.Android,
                    options = BuildOptions.None
                });

                if (report.summary.result != BuildResult.Succeeded)
                {
                    Debug.LogError("Build failed: " + report.summary.result + ", errors: " + report.summary.totalErrors);
                    EditorApplication.Exit(1);
                    return;
                }
                Debug.Log("Build OK: " + output + " (" + report.summary.totalSize / (1024 * 1024) + " MB)");
            }
            catch (Exception e)
            {
                Debug.LogException(e);
                EditorApplication.Exit(1);
            }
        }

        static void Prepare()
        {
            EnsureScene();
            ConfigurePlayer();
            BuildVariantAnchor();
            IncludeShaders();
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
        }

        static void EnsureScene()
        {
            Directory.CreateDirectory("Assets/Scenes");
            // The app builds itself in code (AppBootstrap), so the scene is intentionally empty.
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            EditorSceneManager.SaveScene(scene, ScenePath);
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
        }

        static void ConfigurePlayer()
        {
            EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.Android, BuildTarget.Android);
            EditorUserBuildSettings.buildAppBundle = false;
            EditorUserBuildSettings.androidBuildSystem = AndroidBuildSystem.Gradle;

            PlayerSettings.companyName = "SaintVessel";
            PlayerSettings.productName = "Saint Vessel";
            PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.Android, "com.saintvessel.app");

            string run = Environment.GetEnvironmentVariable("GITHUB_RUN_NUMBER");
            int code = int.TryParse(run, out var n) ? n : 1;
            PlayerSettings.bundleVersion = "1.0." + code;
            PlayerSettings.Android.bundleVersionCode = code;

            PlayerSettings.SetScriptingBackend(BuildTargetGroup.Android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            PlayerSettings.SetManagedStrippingLevel(BuildTargetGroup.Android, ManagedStrippingLevel.Minimal);
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel26;
            PlayerSettings.Android.targetSdkVersion = AndroidSdkVersions.AndroidApiLevelAuto;

            PlayerSettings.SetUseDefaultGraphicsAPIs(BuildTarget.Android, false);
            PlayerSettings.SetGraphicsAPIs(BuildTarget.Android, new[] { UnityEngine.Rendering.GraphicsDeviceType.OpenGLES3 });
            PlayerSettings.colorSpace = ColorSpace.Linear;
            PlayerSettings.gpuSkinning = true;
            PlayerSettings.preserveFramebufferAlpha = true;   // for the alpha/"transparent" background mode

            PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
            PlayerSettings.allowedAutorotateToPortrait = true;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.Android.useCustomKeystore = false;   // debug-signed, directly installable
        }

        /// <summary>
        /// VRMs are loaded at runtime, so Unity can't see which MToon shader variants are needed and strips them (pink avatar).
        /// We import Saint.vrm as an asset, clone its materials (textures removed, keywords kept) into Resources,
        /// which forces the exact variants into the build.
        /// </summary>
        static void BuildVariantAnchor()
        {
            try
            {
                AssetDatabase.ImportAsset(VrmPath, ImportAssetOptions.ForceSynchronousImport);
                var mats = AssetDatabase.LoadAllAssetsAtPath(VrmPath).OfType<Material>().ToList();
                foreach (var guid in AssetDatabase.FindAssets("t:Material", new[] { "Assets/StreamingAssets" }))
                {
                    var m = AssetDatabase.LoadAssetAtPath<Material>(AssetDatabase.GUIDToAssetPath(guid));
                    if (m != null && !mats.Contains(m)) mats.Add(m);
                }
                if (mats.Count == 0)
                {
                    Debug.LogWarning("ShaderVariantAnchor: no materials found in imported Saint.vrm; relying on Always Included Shaders only.");
                    return;
                }

                if (AssetDatabase.IsValidFolder(AnchorDir)) AssetDatabase.DeleteAsset(AnchorDir);
                if (!AssetDatabase.IsValidFolder("Assets/Resources")) AssetDatabase.CreateFolder("Assets", "Resources");
                AssetDatabase.CreateFolder("Assets/Resources", "ShaderVariantAnchor");

                var clones = new System.Collections.Generic.List<Material>();
                int i = 0;
                foreach (var m in mats)
                {
                    var c = new Material(m);
                    foreach (var p in c.GetTexturePropertyNames()) c.SetTexture(p, null);
                    AssetDatabase.CreateAsset(c, $"{AnchorDir}/anchor_{i++}.mat");
                    clones.Add(c);
                }

                const string assetPath = "Assets/Resources/ShaderVariantAnchor.asset";
                AssetDatabase.DeleteAsset(assetPath);
                var anchor = ScriptableObject.CreateInstance<ShaderVariantAnchor>();
                anchor.materials = clones.ToArray();
                AssetDatabase.CreateAsset(anchor, assetPath);
                Debug.Log("ShaderVariantAnchor: " + clones.Count + " materials anchored.");
            }
            catch (Exception e)
            {
                Debug.LogWarning("ShaderVariantAnchor failed (build continues): " + e.Message);
            }
        }

        static void IncludeShaders()
        {
            string[] names =
            {
                "Unlit/Texture", "Unlit/Color", "Standard",
                "VRM10/MToon10", "VRM10/Universal Render Pipeline/MToon10", "VRM/MToon", "VRM/UnlitTexture",
                "UniGLTF/UniUnlit", "UniGLTF/StandardVColor", "Hidden/Internal-Colored"
            };
            var gs = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/GraphicsSettings.asset").FirstOrDefault();
            if (gs == null) return;
            var so = new SerializedObject(gs);
            var arr = so.FindProperty("m_AlwaysIncludedShaders");
            foreach (var n in names)
            {
                var sh = Shader.Find(n);
                if (sh == null) continue;
                bool has = false;
                for (int i = 0; i < arr.arraySize; i++)
                    if (arr.GetArrayElementAtIndex(i).objectReferenceValue == sh) { has = true; break; }
                if (has) continue;
                arr.InsertArrayElementAtIndex(arr.arraySize);
                arr.GetArrayElementAtIndex(arr.arraySize - 1).objectReferenceValue = sh;
            }
            so.ApplyModifiedProperties();
        }
    }
}
