Shader "SceneVolumetricFog"
{
    Properties
    {
        [Header(Cubemap)]
        _Fog_Cubemap("Cubemap", Cube) = "white" {}
        _Fog_Cubemap_Exposure("Exposure", Float) = 1

        [Header(Mip Mapping)]
        [Toggle(USE_CONSTANT_MIP)] _Fog_Cubemap_UseConstantMip("Use Constant Mip", Float) = 1
        _Fog_Cubemap_Mip_MinLevel("Mip Level", Float) = 1
        _Fog_Cubemap_Mip_Distance("Mip Distance", Float) = 1
        _Fog_Cubemap_Mip_Multiplier("Mip Density Multiplier", Float) = 1

        [Header(Fog Main)]
        [Toggle(OCCLUDE_SKY)] _Fog_OccludeSky("Occlude Sky", Float) = 1
        _Fog_StartDistance("Start Distance", Float) = 1
        _Fog_Density("Density", Float) = 1

        [Header(Fog Height)]
        [Toggle(DO_HEIGHT_FOG)] _Fog_DoHeightFog("Enable Height Fog", Float) = 1
        _Fog_Height_StartDistance("Height Distance", Float) = 1
        _Fog_Height_Density("Height Density", Float) = 1
        _Fog_Height("Height", Float) = 1
        _Fog_Height_Falloff("Height Falloff", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent+2000" }

        Cull Off ZWrite Off ZTest Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing  
            #pragma shader_feature_local OCCLUDE_SKY
            #pragma shader_feature_local USE_CONSTANT_MIP
            #pragma shader_feature_local DO_HEIGHT_FOG
            #pragma fragmentoption ARB_precision_hint_fastest
            #include "UnityCG.cginc"

            struct appdata
            {
                fixed4 vertex : POSITION;

                //Single Pass Instanced Support
                UNITY_VERTEX_INPUT_INSTANCE_ID 
            };

            struct v2f
            {
                fixed4 vertex : SV_POSITION;
                fixed4 screenPos : TEXCOORD0;
                fixed3 camRelativeWorldPos : TEXCOORD1;

                //Single Pass Instanced Support
                UNITY_VERTEX_OUTPUT_STEREO
            };

            //cubemap properties
            samplerCUBE _Fog_Cubemap;
            fixed _Fog_Cubemap_Exposure;

            //mip mapping properties
            fixed _Fog_Cubemap_Mip_MinLevel;
            fixed _Fog_Cubemap_Mip_Distance;
            fixed _Fog_Cubemap_Mip_Multiplier;

            //fog properties
            fixed _Fog_StartDistance;
            fixed _Fog_Density;

            //height fog properties
            fixed _Fog_Height_StartDistance;
            fixed _Fog_Height_Density;
            fixed _Fog_Height;
            fixed _Fog_Height_Falloff;

            //sampler2D_float _CameraDepthTexture;
            UNITY_DECLARE_SCREENSPACE_TEXTURE(_CameraDepthTexture);
            fixed4 _CameraDepthTexture_TexelSize;

            v2f vert(appdata v)
            {
                v2f o;

                //Single Pass Instanced Support
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.screenPos = UnityStereoTransformScreenSpaceTex(ComputeScreenPos(o.vertex));
                o.camRelativeWorldPos = mul(unity_ObjectToWorld, fixed4(v.vertex.xyz, 1.0)).xyz - _WorldSpaceCameraPos;

#if UNITY_UV_STARTS_AT_TOP
                if (_CameraDepthTexture_TexelSize.y < 0)
                    o.screenPos.y = 1 - o.screenPos.y;
#endif

#if UNITY_SINGLE_PASS_STEREO
                // If Single-Pass Stereo mode is active, transform the
                // coordinates to get the correct output UV for the current eye.
                fixed4 scaleOffset = unity_StereoScaleOffset[unity_StereoEyeIndex];
                o.screenPos = (o.screenPos - scaleOffset.zw) / scaleOffset.xy;
#endif

                return o;
            }

            fixed ComputeDistance(fixed3 ray, fixed depth)
            {
                return length(ray * depth) - _ProjectionParams.y;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                //Single Pass Instanced Support
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                //get our screen uv coords
                fixed2 screenUV = i.screenPos.xy / i.screenPos.w;

                //draw our scene depth texture
                fixed depth = SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos));
                fixed linearDepth = LinearEyeDepth(depth); //linearize it
                fixed linear01depth = Linear01Depth(depth * (depth < 1.0));

                //calculate the world position view plane for the camera
                fixed3 cameraWorldPositionViewPlane = i.camRelativeWorldPos.xyz / dot(i.camRelativeWorldPos.xyz, unity_WorldToCamera._m20_m21_m22);

                //get the world position vector
                fixed3 worldPos = cameraWorldPositionViewPlane * linearDepth + _WorldSpaceCameraPos;
                fixed3 cameraWorldDir = _WorldSpaceCameraPos.xyz - worldPos.xyz;

                //compute a radial distance (instead of just modifying the regular scene depth buffer for fog since if the camera rotates )
                fixed computedDistance = ComputeDistance(cameraWorldDir.rgb, linear01depth);

                //calculate the main fog
                fixed fog = max(0.0f, (computedDistance - _Fog_StartDistance) * _Fog_Density);
                fog = saturate(fog); //clamp it

#ifdef DO_HEIGHT_FOG
                fixed fog_height = max(0.0f, (computedDistance - _Fog_Height_StartDistance) * _Fog_Height_Density);
                fog_height = lerp(fog_height, 0.0f, (worldPos.y * _Fog_Height_Falloff) - _Fog_Height);
                fog_height = saturate(fog_height);
                fog = saturate(fog + fog_height);
#endif

#ifdef OCCLUDE_SKY
#else
                if (linearDepth > _ProjectionParams.z - 0.001) //if we don't want to occlude the sky, make sure that at the highest depth value (farthest from camera) we don't do any fog.
                    fog = 0.0f;
#endif

#ifdef USE_CONSTANT_MIP
                //use a constant mip level
                fixed mipDistance = _Fog_Cubemap_Mip_MinLevel;
#else 
                //using a fog based mip plevel
                fixed mipDistance = 1 - max(0.0f, (computedDistance - _Fog_Cubemap_Mip_Distance) * _Fog_Cubemap_Mip_Multiplier);
                mipDistance = saturate(mipDistance) * _Fog_Cubemap_Mip_MinLevel;
#endif
                fixed4 cubemap = texCUBElod(_Fog_Cubemap, fixed4(-cameraWorldDir.xyz, mipDistance)) * _Fog_Cubemap_Exposure;

                //return the final fog color
                return fixed4(cubemap.rgb, fog);
            }
            ENDCG
        }
    }
}
