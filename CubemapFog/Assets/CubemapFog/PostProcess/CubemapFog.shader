Shader "Hidden/CubemapFog"
{
	SubShader
	{
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			HLSLPROGRAM
			#pragma vertex Vert
			#pragma fragment Frag
			#pragma shader_feature_local OCCLUDE_SKY
			#pragma shader_feature_local USE_CONSTANT_MIP
			#pragma shader_feature_local DO_HEIGHT_FOG
			#pragma fragmentoption ARB_precision_hint_fastest
			#include "Packages/com.unity.postprocessing/PostProcessing/Shaders/StdLib.hlsl"

			TEXTURE2D_SAMPLER2D(_MainTex, sampler_MainTex);
			TEXTURE2D_SAMPLER2D(_CameraDepthTexture, sampler_CameraDepthTexture);
			float4 _MainTex_TexelSize;
			float4x4 _ClipToView;
			float4x4 _ViewProjInv;

			//cubemap properties
			samplerCUBE _Fog_Cubemap;
			float _Fog_Cubemap_Exposure;

			//mip mapping properties
			float _Fog_Cubemap_Mip_MinLevel;
			float _Fog_Cubemap_Mip_Distance;
			float _Fog_Cubemap_Mip_Multiplier;

			//main fog properties
			float _Intensity;
			float _Fog_StartDistance;
			float _Fog_Density;

			//height fog
			float _Fog_Height_StartDistance;
			float _Fog_Height_Density;
			float _Fog_Height;
			float _Fog_Height_Falloff;

			//debugging
			float4 DebugModes; //x = classic fog, y = height fog, z = mip distance, w = cubemap only

			struct NewAttributesDefault
			{
				float3 vertex : POSITION;
				float4 texcoord : TEXCOORD;
			};

			struct Varyings
			{
				float4 vertex : SV_POSITION;
				float2 texcoord : TEXCOORD0;
				float2 texcoordStereo : TEXCOORD1;
				float3 viewSpaceDir : TEXCOORD2;
				float3 ray : TEXCOORD3;

				#if STEREO_INSTANCING_ENABLED
					uint stereoTargetEyeIndex : SV_RenderTargetArrayIndex;
				#endif
			};

			Varyings Vert(NewAttributesDefault v)
			{
				Varyings o;

				o.vertex = float4(v.vertex.xy, 0.0, 1.0);
				o.texcoord = TransformTriangleVertexToUV(v.vertex.xy);
				o.viewSpaceDir = mul(_ClipToView, o.vertex).xyz;
				o.ray = v.texcoord.xyz;

				#if UNITY_UV_STARTS_AT_TOP
					o.texcoord = o.texcoord * float2(1.0, -1.0) + float2(0.0, 1.0);
				#endif

				o.texcoordStereo = TransformStereoScreenSpaceTex(o.texcoord, 1.0);

				return o;
			}

			float ComputeDistance(float3 ray, float depth)
			{
				return length(ray * depth) - _ProjectionParams.y;
			}

			float GetDepth(float2 uv)
			{
				return SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r;
			}

			float4 GetWorldPositionFromDepth(float2 uv_depth)
			{
				float depth = GetDepth(uv_depth);

				#if defined(SHADER_API_OPENGL)
					depth = depth * 2.0 - 1.0;
				#endif

				float4 H = float4(uv_depth.x * 2.0 - 1.0, (uv_depth.y) * 2.0 - 1.0, depth, 1.0);
				float4 D = mul(_ViewProjInv, H);

				return D / D.w;
			}

			float4 Frag(Varyings i) : SV_Target
			{
				float2 uv = i.texcoordStereo.xy;

				float zsample = GetDepth(uv);
				float4 worldPos = GetWorldPositionFromDepth(uv);
				float4 cameraWorldPos = mul(unity_ObjectToWorld, worldPos);
				float3 cameraWorldDir = _WorldSpaceCameraPos.xyz - worldPos.xyz;

				float depth = Linear01Depth(zsample * (zsample < 1.0));
				float computedDistance = ComputeDistance(cameraWorldDir.rgb, depth);

				float fog = max(0.0f, (computedDistance - _Fog_StartDistance) * _Fog_Density);
				fog = saturate(fog);

#ifdef DO_HEIGHT_FOG
				float fog_height = max(0.0f, (computedDistance - _Fog_Height_StartDistance) * _Fog_Height_Density);
				fog_height = lerp(fog_height, 0.0f, (worldPos.y * _Fog_Height_Falloff) - _Fog_Height);
				fog_height = saturate(fog_height);
				fog = saturate(fog + fog_height);
#endif

#ifdef OCCLUDE_SKY
#else
				if (depth == 1.0f)
					fog = 0.0f;
#endif

#ifdef USE_CONSTANT_MIP
				float mipDistance = _Fog_Cubemap_Mip_MinLevel;
#else
				float mipDistance = 1 - max(0.0f, (computedDistance - _Fog_Cubemap_Mip_Distance) * _Fog_Cubemap_Mip_Multiplier);
				mipDistance = saturate(mipDistance) * _Fog_Cubemap_Mip_MinLevel;
#endif
				float4 cubemap = texCUBElod(_Fog_Cubemap, float4(-cameraWorldDir.xyz, mipDistance)) * _Fog_Cubemap_Exposure;

				float4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
				fog = lerp(fog, 0.0f, 1 - _Intensity);
				color.rgb = lerp(color.rgb, cubemap.rgb, fog);

				if (DebugModes.x > 0) //view classic fog
					return float4(fog, fog, fog, 1.0);
				else if (DebugModes.z > 0) //view mip level distance
					return float4(mipDistance, mipDistance, mipDistance, mipDistance);
				else if (DebugModes.w > 0) //view cubemap only
					return cubemap;

				return color;
			}

			ENDHLSL
		}
	}
}
