Shader "SceneVolumetricFog"
{
    Properties
    {
        [Header(Cubemap)]
        _Fog_Cubemap("Cubemap", Cube) = "white" {}
        _Fog_Cubemap_Exposure("Exposure", Float) = 1

        [Header(Mip Mapping)]
        [Toggle] _Fog_Cubemap_UseConstantMip("Use Constant Mip", Float) = 1
        _Fog_Cubemap_Mip_MinLevel("Mip Level", Float) = 1
        _Fog_Cubemap_Mip_Distance("Mip Distance", Float) = 1
        _Fog_Cubemap_Mip_Multiplier("Mip Density Multiplier", Float) = 1

        [Header(Fog Main)]
        [Toggle] _Fog_OccludeSky("Occlude Sky", Float) = 1
        _Fog_StartDistance("Start Distance", Float) = 1
        _Fog_Density("Density", Float) = 1

        [Header(Fog Height)]
        _Fog_Height_StartDistance("Height Distance", Float) = 1
        _Fog_Height_Density("Height Density", Float) = 1
        _Fog_Height("Height", Float) = 1
        _Fog_Height_Falloff("Height Falloff", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent+2000" }

        Cull Off
        ZWrite Off
        ZTest Off

        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing  
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
                float2 depth : TEXCOORD2;

                //Single Pass Instanced Support
                UNITY_VERTEX_OUTPUT_STEREO
            };

            samplerCUBE _Fog_Cubemap;

            float _Fog_Cubemap_UseConstantMip;
            float _Fog_Cubemap_Mip_MinLevel;
            float _Fog_Cubemap_Mip_Distance;
            float _Fog_Cubemap_Mip_Multiplier;
            float _Fog_Cubemap_Exposure;

            float _Fog_StartDistance;
            float _Fog_Density;

            float _Fog_Height_StartDistance;
            float _Fog_Height_Density;
            float _Fog_Height;
            float _Fog_Height_Falloff;
            float _Fog_OccludeSky;

            //other shader values
            float2 CamValues; //x = farplane, y = nearplane
            float4 DebugModes; //x = classic fog, y = height fog, z = mip distance, w = cubemap only

            UNITY_DECLARE_SCREENSPACE_TEXTURE(_CameraDepthTexture);
            //sampler2D_float _CameraDepthTexture;
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

                return o;
            }

            float ComputeDistance(float3 ray, float depth)
            {
                float dist;

                dist = length(ray * depth);
                dist -= _ProjectionParams.y;

                return dist;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                //Single Pass Instanced Support
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                //get our screen uv coords
                fixed2 screenUV = i.screenPos.xy / i.screenPos.w;


#if UNITY_UV_STARTS_AT_TOP
                if (_CameraDepthTexture_TexelSize.y < 0) 
                    screenUV.y = 1 - screenUV.y;
#endif

#if UNITY_SINGLE_PASS_STEREO
                // If Single-Pass Stereo mode is active, transform the
                // coordinates to get the correct output UV for the current eye.
                float4 scaleOffset = unity_StereoScaleOffset[unity_StereoEyeIndex];
                screenUV = (screenUV - scaleOffset.zw) / scaleOffset.xy;
#endif

                fixed depth = SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos));

                //draw our scene depth texture and linearize it
                fixed linearDepth = LinearEyeDepth(depth);

                //calculate the world position view plane for the camera
                fixed3 cameraWorldPositionViewPlane = i.camRelativeWorldPos.xyz / dot(i.camRelativeWorldPos.xyz, unity_WorldToCamera._m20_m21_m22);

                //get the world position vector
                fixed3 worldPos = cameraWorldPositionViewPlane * linearDepth + _WorldSpaceCameraPos;

                float3 cameraWorldDir = _WorldSpaceCameraPos.xyz - worldPos.xyz;
                float linear01depth = Linear01Depth(depth * (depth < 1.0));
                float computedDistance = ComputeDistance(cameraWorldDir.rgb, linear01depth);

                float fog = max(0.0f, (computedDistance - _Fog_StartDistance) * _Fog_Density);
                float fog_height = max(0.0f, (computedDistance - _Fog_Height_StartDistance) * _Fog_Height_Density);
                fog_height = lerp(fog_height, 0.0f, (worldPos.y * _Fog_Height_Falloff) - _Fog_Height);

                fog = saturate(fog);
                fog_height = saturate(fog_height);

                if (depth == 1.0f && _Fog_OccludeSky < 1)
                {
                    fog = 0.0f;
                    fog_height = 0.0f;
                }

                float4 cubemap = float4(0, 0, 0, 0);
                float mipDistance = 0.0f;

                if (_Fog_Cubemap_UseConstantMip > 0) //use a constant mip level?
                {
                    cubemap = texCUBElod(_Fog_Cubemap, float4(-cameraWorldDir.xyz, _Fog_Cubemap_Mip_MinLevel)) * _Fog_Cubemap_Exposure;
                }
                else //using a fog based mip plevel
                {
                    mipDistance = 1 - max(0.0f, (computedDistance - _Fog_Cubemap_Mip_Distance) * _Fog_Cubemap_Mip_Multiplier);
                    mipDistance = saturate(mipDistance) * _Fog_Cubemap_Mip_MinLevel;

                    cubemap = texCUBElod(_Fog_Cubemap, float4(-cameraWorldDir.xyz, mipDistance)) * _Fog_Cubemap_Exposure;
                }

                float4 result = float4(cubemap.rgb, saturate(fog + fog_height));
                //result.rgb = lerp(color.rgb, cubemap.rgb, fog);
                //result.rgb = lerp(color.rgb, cubemap.rgb, fog_height);

                //return the final fog color
                return result;
            }
            ENDCG
        }
    }
}
