#if UNITY_EDITOR

using System.IO;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine.Rendering;

namespace CubemapFog
{
    public class GenerateSkyCubemap : EditorWindow
    {
        public struct TextureObjectSettings
        {
            public TextureWrapMode wrapMode;
            public FilterMode filterMode;
            public int anisoLevel;
        }

        public struct TextureObjectCUBE
        {
            public Texture2D X_Positive;
            public Texture2D Y_Positive;
            public Texture2D Z_Positive;
            public Texture2D X_Negative;
            public Texture2D Y_Negative;
            public Texture2D Z_Negative;
        }

        //GUI related
        private GUIStyle titleBar;
        private static int guiSectionSpacePixels = 10;
        private static Vector2Int windowSize = new Vector2Int(350, 150);
        private static TextureFormat assetFormat = TextureFormat.RGBAHalf;

        //options
        private string cubemapName = "CubemapFog";
        private int cubemapResolution = 128;
        private bool specularConvolution = true;

        //add a menu item at the top of the unity editor toolbar
        [MenuItem("Cubemap Fog/Generate Sky Cubemap")]
        public static void ShowWindow()
        {
            //get the window and open it
            GetWindow(typeof(GenerateSkyCubemap));
        }

        /// <summary>
        /// GUI display function for the window
        /// </summary>
        void OnGUI()
        {
            maxSize = windowSize;
            minSize = windowSize;

            if (titleBar == null)
            {
                titleBar = new GUIStyle(EditorStyles.label);
                titleBar.normal.background = Texture2D.grayTexture;
            }

            //window title
            GUILayout.BeginVertical(titleBar);
            GUILayout.Label("Generate Sky Cubemap", EditorStyles.whiteLargeLabel);
            GUILayout.EndVertical();
            GUILayout.Space(guiSectionSpacePixels);

            cubemapName = EditorGUILayout.TextField("Cubemap Name", cubemapName);
            cubemapResolution = EditorGUILayout.IntField("Cubemap Resolution", cubemapResolution);
            specularConvolution = EditorGUILayout.Toggle("Specular Convolution", specularConvolution);

            GUILayout.Space(guiSectionSpacePixels);

            if (GUILayout.Button("Generate"))
            {
                ConverToUnityStaticSkybox();
            }
        }

        public void ConverToUnityStaticSkybox()
        {
            UnityEngine.SceneManagement.Scene activeScene = EditorSceneManager.GetActiveScene();
            string sceneFolder = Path.GetDirectoryName(activeScene.path);

            //create our camera object and set it up
            GameObject cameraCubeGameObject = new GameObject("TEMP_cameraCubeGameObject");
            Camera cameraCube = cameraCubeGameObject.AddComponent<Camera>();

            cameraCube.fieldOfView = 90.0f;
            cameraCube.nearClipPlane = 0.03f;
            cameraCube.farClipPlane = 1.0f;
            cameraCube.clearFlags = CameraClearFlags.Skybox;
            cameraCube.cullingMask = 0;
            cameraCube.allowHDR = true;

            //create a temp RT and assign it to the camera
            RenderTexture staticSkyRT = new RenderTexture(cubemapResolution, cubemapResolution, 0, RenderTextureFormat.DefaultHDR);
            staticSkyRT.dimension = TextureDimension.Cube;
            cameraCube.targetTexture = staticSkyRT;

            //-----------------------------sky-----------------------------
            //-----------------------------sky-----------------------------
            //-----------------------------sky-----------------------------

            //create our helper object
            TextureObjectSettings rtSettings = new TextureObjectSettings() { anisoLevel = 0, filterMode = FilterMode.Bilinear, wrapMode = TextureWrapMode.Clamp };

            //render each cubemap face
            //front (+X)  
            cameraCube.transform.Rotate(0, 90, 0);
            cameraCube.Render();
            SaveCUBE_Face(staticSkyRT, sceneFolder + "/", "X_POS", rtSettings);

            //right (-Z)
            cameraCube.transform.Rotate(0, 90, 0);
            cameraCube.Render();
            SaveCUBE_Face(staticSkyRT, sceneFolder + "/", "Z_NEG", rtSettings);

            //back (-X)
            cameraCube.transform.Rotate(0, 90, 0);
            cameraCube.Render();
            SaveCUBE_Face(staticSkyRT, sceneFolder + "/", "X_NEG", rtSettings);

            //left (+Z)
            cameraCube.transform.Rotate(0, 90, 0);
            cameraCube.Render();
            SaveCUBE_Face(staticSkyRT, sceneFolder + "/", "Z_POS", rtSettings);

            //+Y  (up) (left then up)
            cameraCube.transform.Rotate(90, 0, 0);
            cameraCube.Render();
            SaveCUBE_Face(staticSkyRT, sceneFolder + "/", "Y_POS", rtSettings);

            //-Y (down) (left then down)
            cameraCube.transform.Rotate(180, 0, 0);
            cameraCube.Render();
            SaveCUBE_Face(staticSkyRT, sceneFolder + "/", "Y_NEG", rtSettings);

            //finally we combine them
            TextureObjectCUBE finalSky_faces = new TextureObjectCUBE()
            {
                X_Positive = AssetDatabase.LoadAssetAtPath<Texture2D>(string.Format("{0}/{1}_CUBE_X_POS.exr", sceneFolder, cubemapName)),
                Y_Positive = AssetDatabase.LoadAssetAtPath<Texture2D>(string.Format("{0}/{1}_CUBE_Y_POS.exr", sceneFolder, cubemapName)),
                Z_Positive = AssetDatabase.LoadAssetAtPath<Texture2D>(string.Format("{0}/{1}_CUBE_Z_POS.exr", sceneFolder, cubemapName)),
                X_Negative = AssetDatabase.LoadAssetAtPath<Texture2D>(string.Format("{0}/{1}_CUBE_X_NEG.exr", sceneFolder, cubemapName)),
                Y_Negative = AssetDatabase.LoadAssetAtPath<Texture2D>(string.Format("{0}/{1}_CUBE_Y_NEG.exr", sceneFolder, cubemapName)),
                Z_Negative = AssetDatabase.LoadAssetAtPath<Texture2D>(string.Format("{0}/{1}_CUBE_Z_NEG.exr", sceneFolder, cubemapName))
            };

            CombineCUBE(finalSky_faces, sceneFolder + "/", rtSettings);

            //remove the camera from the scene
            DestroyImmediate(cameraCubeGameObject);
        }

        public void SaveCUBE_Face(RenderTexture rt, string directory, string faceIndex, TextureObjectSettings settings)
        {
            //create our texture2D object to store the slice
            Texture2D output = new Texture2D(rt.width, rt.height, assetFormat, false);
            output.anisoLevel = settings.anisoLevel;
            output.wrapMode = settings.wrapMode;
            output.filterMode = settings.filterMode;

            //make sure the render texture slice is active so we can read from it
            RenderTexture.active = rt;

            //read the texture and store the data in the texture2D object
            output.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
            output.Apply();

            RenderTexture.active = null;

            //save the asset to disk
            if (Directory.Exists(Path.GetDirectoryName(Application.dataPath) + "/" + directory) == false)
                Directory.CreateDirectory(Path.GetDirectoryName(Application.dataPath) + "/" + directory);

            string assetPath = directory + cubemapName + "_CUBE_" + faceIndex + ".exr";
            string assetSystemPath = Path.GetDirectoryName(Application.dataPath) + "/" + assetPath;

            AssetDatabase.DeleteAsset(assetPath);
            File.WriteAllBytes(assetSystemPath, output.EncodeToEXR());
            AssetDatabase.ImportAsset(assetPath);

            Texture2D loadedTexture = AssetDatabase.LoadAssetAtPath<Texture2D>(assetPath);
            TextureImporter textureImporter = (TextureImporter)TextureImporter.GetAtPath(assetPath);

            if (loadedTexture.isReadable != true)
            {
                textureImporter.isReadable = true;
                textureImporter.SaveAndReimport();
            }
        }

        public void CombineCUBE(TextureObjectCUBE faceTextures, string directory, TextureObjectSettings settings)
        {
            int cubemapFullHeightSize = faceTextures.X_Positive.height;
            int cubemapFullWidthSize = faceTextures.X_Positive.width * 6;

            int cubemapSingleHeightSize = faceTextures.X_Positive.height;
            int cubemapSingleWidthSize = faceTextures.X_Positive.width;

            Texture2D output = new Texture2D(cubemapFullWidthSize, cubemapFullHeightSize, assetFormat, false);
            output.anisoLevel = settings.anisoLevel;
            output.wrapMode = settings.wrapMode;
            output.filterMode = settings.filterMode;

            //x pos
            for (int x = 0; x < cubemapSingleWidthSize; x++)
            {
                for (int y = 0; y < cubemapSingleHeightSize; y++)
                {
                    Vector2Int pixelPosFull = new Vector2Int(x + (cubemapSingleWidthSize * 0), y);
                    Vector2Int pixelPosFace = new Vector2Int(x, y);

                    Color pixelColorFace = faceTextures.X_Positive.GetPixel(pixelPosFace.x, pixelPosFace.y);

                    output.SetPixel(pixelPosFull.x, pixelPosFull.y, pixelColorFace);
                }
            }

            //x neg
            for (int x = 0; x < cubemapSingleWidthSize; x++)
            {
                for (int y = 0; y < cubemapSingleHeightSize; y++)
                {
                    Vector2Int pixelPosFull = new Vector2Int(x + (cubemapSingleWidthSize * 1), y);
                    Vector2Int pixelPosFace = new Vector2Int(x, y);

                    Color pixelColorFace = faceTextures.X_Negative.GetPixel(pixelPosFace.x, pixelPosFace.y);

                    output.SetPixel(pixelPosFull.x, pixelPosFull.y, pixelColorFace);
                }
            }

            //y neg
            for (int x = 0; x < cubemapSingleWidthSize; x++)
            {
                for (int y = 0; y < cubemapSingleHeightSize; y++)
                {
                    Vector2Int pixelPosFull = new Vector2Int(x + (cubemapSingleWidthSize * 2), y);
                    Vector2Int pixelPosFace = new Vector2Int(x, y);

                    Color pixelColorFace = faceTextures.Y_Negative.GetPixel(pixelPosFace.x, pixelPosFace.y);

                    output.SetPixel(pixelPosFull.x, pixelPosFull.y, pixelColorFace);
                }
            }

            //y pos
            for (int x = 0; x < cubemapSingleWidthSize; x++)
            {
                for (int y = 0; y < cubemapSingleHeightSize; y++)
                {
                    Vector2Int pixelPosFull = new Vector2Int(x + (cubemapSingleWidthSize * 3), y);
                    Vector2Int pixelPosFace = new Vector2Int(x, y);

                    Color pixelColorFace = faceTextures.Y_Positive.GetPixel(pixelPosFace.x, pixelPosFace.y);

                    output.SetPixel(pixelPosFull.x, pixelPosFull.y, pixelColorFace);
                }
            }

            //z pos
            for (int x = 0; x < cubemapSingleWidthSize; x++)
            {
                for (int y = 0; y < cubemapSingleHeightSize; y++)
                {
                    Vector2Int pixelPosFull = new Vector2Int(x + (cubemapSingleWidthSize * 4), y);
                    Vector2Int pixelPosFace = new Vector2Int(x, y);

                    Color pixelColorFace = faceTextures.Z_Positive.GetPixel(pixelPosFace.x, pixelPosFace.y);

                    output.SetPixel(pixelPosFull.x, pixelPosFull.y, pixelColorFace);
                }
            }

            //z neg
            for (int x = 0; x < cubemapSingleWidthSize; x++)
            {
                for (int y = 0; y < cubemapSingleHeightSize; y++)
                {
                    Vector2Int pixelPosFull = new Vector2Int(x + (cubemapSingleWidthSize * 5), y);
                    Vector2Int pixelPosFace = new Vector2Int(x, y);

                    Color pixelColorFace = faceTextures.Z_Negative.GetPixel(pixelPosFace.x, pixelPosFace.y);

                    output.SetPixel(pixelPosFull.x, pixelPosFull.y, pixelColorFace);
                }
            }

            output.Apply();

            //save the asset to disk
            if (Directory.Exists(Path.GetDirectoryName(Application.dataPath) + "/" + directory) == false)
                Directory.CreateDirectory(Path.GetDirectoryName(Application.dataPath) + "/" + directory);

            string assetPath = directory + cubemapName + "_CUBE.exr";
            string assetSystemPath = Path.GetDirectoryName(Application.dataPath) + "/" + assetPath;

            AssetDatabase.DeleteAsset(assetPath);
            File.WriteAllBytes(assetSystemPath, output.EncodeToEXR());
            AssetDatabase.ImportAsset(assetPath);

            //workaround because we can't set the texture shape on the texture object itself directly... stupid unity
            Texture2D loadedTexture = AssetDatabase.LoadAssetAtPath<Texture2D>(assetPath);
            TextureImporter textureImporter = (TextureImporter)TextureImporter.GetAtPath(assetPath);
            TextureImporterSettings textureImporterSettings = new TextureImporterSettings();

            if (loadedTexture.dimension != TextureDimension.Cube)
            {
                textureImporterSettings.seamlessCubemap = true;
                textureImporterSettings.textureShape = TextureImporterShape.TextureCube;
                textureImporterSettings.generateCubemap = TextureImporterGenerateCubemap.FullCubemap;
                textureImporterSettings.filterMode = FilterMode.Trilinear;
                textureImporterSettings.mipmapEnabled = true;

                if (specularConvolution)
                    textureImporterSettings.cubemapConvolution = TextureImporterCubemapConvolution.Specular;

                textureImporter.SetTextureSettings(textureImporterSettings);
                textureImporter.SaveAndReimport();
            }

            //remove the other faces since we don't need them anymore
            AssetDatabase.DeleteAsset(AssetDatabase.GetAssetPath(faceTextures.X_Positive));
            AssetDatabase.DeleteAsset(AssetDatabase.GetAssetPath(faceTextures.X_Negative));
            AssetDatabase.DeleteAsset(AssetDatabase.GetAssetPath(faceTextures.Y_Positive));
            AssetDatabase.DeleteAsset(AssetDatabase.GetAssetPath(faceTextures.Y_Negative));
            AssetDatabase.DeleteAsset(AssetDatabase.GetAssetPath(faceTextures.Z_Positive));
            AssetDatabase.DeleteAsset(AssetDatabase.GetAssetPath(faceTextures.Z_Negative));
        }
    }
}

#endif