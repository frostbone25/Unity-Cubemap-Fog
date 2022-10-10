using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering.PostProcessing;

namespace CubemapFog
{
    [Serializable]
    [PostProcess(typeof(CubemapFogRenderer), PostProcessEvent.BeforeTransparent, "Custom/CustomFog")]
    public sealed class CubemapFog : PostProcessEffectSettings
    {
        [Header("Cubemap")]
        public TextureParameter fogCubemap = new TextureParameter();
        public FloatParameter fogCubemapExposure = new FloatParameter() { value = 1.0f };

        [Header("Mip Mapping Properties")]
        public BoolParameter fogUseConstantMip = new BoolParameter();
        public FloatParameter fogCubemapMipLevel = new FloatParameter();
        public FloatParameter fogCubemapMipDistance = new FloatParameter();
        public FloatParameter fogCubemapMipMultiplier = new FloatParameter() { value = 1.0f };

        [Header("Main Fog Properties")]
        [Range(0f, 1f)] public FloatParameter intensity = new FloatParameter() { value = 1.0f };
        public BoolParameter fogOccludeSky = new BoolParameter();
        public FloatParameter fogStartDistance = new FloatParameter();
        public FloatParameter fogDensity = new FloatParameter() { value = 1.0f };

        [Header("Height Fog")]
        public BoolParameter heightEnable = new BoolParameter();
        public FloatParameter heightFogStartDistance = new FloatParameter();
        public FloatParameter heightFogDensity = new FloatParameter() { value = 1.0f };
        public FloatParameter heightFogHeight = new FloatParameter();
        public FloatParameter heightFogFallof = new FloatParameter() { value = 1.0f };

        [Header("Debug")]
        public BoolParameter viewFog = new BoolParameter();
        public BoolParameter viewMipDistance = new BoolParameter();
        public BoolParameter viewCubemap = new BoolParameter();
    }

    public sealed class CubemapFogRenderer : PostProcessEffectRenderer<CubemapFog>
    {
        public override void Render(PostProcessRenderContext context)
        {
            var sheet = context.propertySheets.Get(Shader.Find("Hidden/CubemapFog"));

            //|||||||||||||||||||||||||||||||||||||| CUBEMAP PROPERTIES ||||||||||||||||||||||||||||||||||||||
            //|||||||||||||||||||||||||||||||||||||| CUBEMAP PROPERTIES ||||||||||||||||||||||||||||||||||||||
            //|||||||||||||||||||||||||||||||||||||| CUBEMAP PROPERTIES ||||||||||||||||||||||||||||||||||||||
            var cubeTex = settings.fogCubemap.value == null ? RuntimeUtilities.blackTexture : settings.fogCubemap.value;

            sheet.properties.SetTexture("_Fog_Cubemap", cubeTex);
            sheet.properties.SetFloat("_Fog_Cubemap_Exposure", settings.fogCubemapExposure.value);

            //|||||||||||||||||||||||||||||||||||||| MAIN PROPERTIES ||||||||||||||||||||||||||||||||||||||
            //|||||||||||||||||||||||||||||||||||||| MAIN PROPERTIES ||||||||||||||||||||||||||||||||||||||
            //|||||||||||||||||||||||||||||||||||||| MAIN PROPERTIES ||||||||||||||||||||||||||||||||||||||
            sheet.properties.SetFloat("_Intensity", settings.intensity.value);
            sheet.properties.SetFloat("_Fog_StartDistance", settings.fogStartDistance.value);
            sheet.properties.SetFloat("_Fog_Density", settings.fogDensity.value);

            if (settings.fogOccludeSky.value)
                sheet.EnableKeyword("OCCLUDE_SKY");
            else
                sheet.DisableKeyword("OCCLUDE_SKY");

            //|||||||||||||||||||||||||||||||||||||| MIP MAP PROPERTIES ||||||||||||||||||||||||||||||||||||||
            //|||||||||||||||||||||||||||||||||||||| MIP MAP PROPERTIES ||||||||||||||||||||||||||||||||||||||
            //|||||||||||||||||||||||||||||||||||||| MIP MAP PROPERTIES ||||||||||||||||||||||||||||||||||||||
            if (settings.fogUseConstantMip.value)
                sheet.EnableKeyword("USE_CONSTANT_MIP");
            else
                sheet.DisableKeyword("USE_CONSTANT_MIP");

            sheet.properties.SetFloat("_Fog_Cubemap_Mip_MinLevel", settings.fogCubemapMipLevel.value);
            sheet.properties.SetFloat("_Fog_Cubemap_Mip_Distance", settings.fogCubemapMipDistance.value);
            sheet.properties.SetFloat("_Fog_Cubemap_Mip_Multiplier", settings.fogCubemapMipMultiplier.value);

            //|||||||||||||||||||||||||||||||||||||| HEIGHT FOG PROPERTIES ||||||||||||||||||||||||||||||||||||||
            //|||||||||||||||||||||||||||||||||||||| HEIGHT FOG PROPERTIES ||||||||||||||||||||||||||||||||||||||
            //|||||||||||||||||||||||||||||||||||||| HEIGHT FOG PROPERTIES ||||||||||||||||||||||||||||||||||||||
            if (settings.heightEnable.value)
                sheet.EnableKeyword("DO_HEIGHT_FOG");
            else
                sheet.DisableKeyword("DO_HEIGHT_FOG");

            sheet.properties.SetFloat("_Fog_Height_StartDistance", settings.heightFogStartDistance.value);
            sheet.properties.SetFloat("_Fog_Height_Density", settings.heightFogDensity.value);
            sheet.properties.SetFloat("_Fog_Height", settings.heightFogHeight.value);
            sheet.properties.SetFloat("_Fog_Height_Falloff", settings.heightFogFallof.value);

            //|||||||||||||||||||||||||||||||||||||| DEBUG PROPERTIES ||||||||||||||||||||||||||||||||||||||
            //|||||||||||||||||||||||||||||||||||||| DEBUG PROPERTIES ||||||||||||||||||||||||||||||||||||||
            //|||||||||||||||||||||||||||||||||||||| DEBUG PROPERTIES ||||||||||||||||||||||||||||||||||||||
            Vector4 debugModes = new Vector4(settings.viewFog.value ? 1 : 0, 0, settings.viewMipDistance.value ? 1 : 0, settings.viewCubemap.value ? 1 : 0);
            sheet.properties.SetVector("DebugModes", debugModes);

            //|||||||||||||||||||||||||||||||||||||| FINAL ||||||||||||||||||||||||||||||||||||||
            //|||||||||||||||||||||||||||||||||||||| FINAL ||||||||||||||||||||||||||||||||||||||
            //|||||||||||||||||||||||||||||||||||||| FINAL ||||||||||||||||||||||||||||||||||||||
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