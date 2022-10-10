using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering.PostProcessing;

namespace VRProject1_PostProcessing
{
    [Serializable]
    [PostProcess(typeof(CubemapFogRenderer), PostProcessEvent.BeforeTransparent, "Custom/CustomFog")]
    public sealed class CubemapFog : PostProcessEffectSettings
    {
        [Range(0f, 1f)]
        public FloatParameter intensity = new FloatParameter() { value = 1.0f };

        [Header("Main Properties")]
        public TextureParameter fogCubemap = new TextureParameter();
        public BoolParameter fogOccludeSky = new BoolParameter();
        public FloatParameter fogCubemapExposure = new FloatParameter() { value = 1.0f };
        public BoolParameter fogUseConstantMip = new BoolParameter();
        public FloatParameter fogCubemapMipLevel = new FloatParameter();
        public FloatParameter fogCubemapMipDistance = new FloatParameter();
        public FloatParameter fogCubemapMipMultiplier = new FloatParameter() { value = 1.0f };

        [Header("Fog")]
        public FloatParameter fogStartDistance = new FloatParameter();
        public FloatParameter fogDensity = new FloatParameter() { value = 1.0f };

        [Header("Height Fog")]
        public FloatParameter heightFogStartDistance = new FloatParameter();
        public FloatParameter heightFogDensity = new FloatParameter() { value = 1.0f };
        public FloatParameter heightFogHeight = new FloatParameter();
        public FloatParameter heightFogFallof = new FloatParameter() { value = 1.0f };

        [Header("Debug")]
        public BoolParameter viewFog = new BoolParameter();
        public BoolParameter viewHeightFog = new BoolParameter();
        public BoolParameter viewMipDistance = new BoolParameter();
        public BoolParameter viewCubemap = new BoolParameter();
    }

    public sealed class CubemapFogRenderer : PostProcessEffectRenderer<CubemapFog>
    {
        public override void Render(PostProcessRenderContext context)
        {
            var sheet = context.propertySheets.Get(Shader.Find("Hidden/CubemapFog"));
            var cubeTex = settings.fogCubemap.value == null ? RuntimeUtilities.blackTexture : settings.fogCubemap.value;

            Vector4 debugModes = new Vector4(settings.viewFog.value ? 1 : 0, settings.viewHeightFog.value ? 1 : 0, settings.viewMipDistance.value ? 1 : 0, settings.viewCubemap.value ? 1 : 0);

            //effect intensity
            sheet.properties.SetFloat("_Intensity", settings.intensity.value);

            //main properties
            sheet.properties.SetTexture("_Fog_Cubemap", cubeTex);
            sheet.properties.SetFloat("_Fog_OccludeSky", settings.fogOccludeSky.value ? 1 : 0);
            sheet.properties.SetFloat("_Fog_Cubemap_Exposure", settings.fogCubemapExposure.value);
            sheet.properties.SetFloat("_Fog_Cubemap_UseConstantMip", settings.fogUseConstantMip.value ? 1 : 0);
            sheet.properties.SetFloat("_Fog_Cubemap_Mip_MinLevel", settings.fogCubemapMipLevel.value);
            sheet.properties.SetFloat("_Fog_Cubemap_Mip_Distance", settings.fogCubemapMipDistance.value);
            sheet.properties.SetFloat("_Fog_Cubemap_Mip_Multiplier", settings.fogCubemapMipMultiplier.value);

            //fog props
            sheet.properties.SetFloat("_Fog_StartDistance", settings.fogStartDistance.value);
            sheet.properties.SetFloat("_Fog_Density", settings.fogDensity.value);

            //height fog props
            sheet.properties.SetFloat("_Fog_Height_StartDistance", settings.heightFogStartDistance.value);
            sheet.properties.SetFloat("_Fog_Height_Density", settings.heightFogDensity.value);
            sheet.properties.SetFloat("_Fog_Height", settings.heightFogHeight.value);
            sheet.properties.SetFloat("_Fog_Height_Falloff", settings.heightFogFallof.value);

            //other shader values
            sheet.properties.SetVector("DebugModes", debugModes);
            sheet.properties.SetVector("CamValues", new Vector2(context.camera.farClipPlane, context.camera.nearClipPlane));

            Matrix4x4 clipToView = GL.GetGPUProjectionMatrix(context.camera.projectionMatrix, true).inverse;
            sheet.properties.SetMatrix("_ClipToView", clipToView);

            Matrix4x4 viewMat = context.camera.worldToCameraMatrix;
            Matrix4x4 projMat = GL.GetGPUProjectionMatrix(context.camera.projectionMatrix, false);
            Matrix4x4 viewProjMat = (projMat * viewMat);
            Shader.SetGlobalMatrix("_ViewProjInv", viewProjMat.inverse);

            context.command.BlitFullscreenTriangle(context.source, context.destination, sheet, 0);
        }
    }
}