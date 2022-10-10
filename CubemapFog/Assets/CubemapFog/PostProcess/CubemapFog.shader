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
			#include "Packages/com.unity.postprocessing/PostProcessing/Shaders/StdLib.hlsl"

			TEXTURE2D_SAMPLER2D(_MainTex, sampler_MainTex);
			TEXTURE2D_SAMPLER2D(_CameraDepthTexture, sampler_CameraDepthTexture);
			samplerCUBE _Fog_Cubemap;

			float4 _MainTex_TexelSize;
			float4x4 _ClipToView;
			float4x4 _ViewProjInv;

			float _Intensity;
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

			float CustomLuminance(float3 color)
			{
				float4 colorSpace = float4(0.22, 0.707, 0.071, 0.0);
				return dot(color, colorSpace.rgb);
			}

			float ComputeDistance(float3 ray, float depth)
			{
				float dist;

				dist = length(ray * depth);
				dist -= _ProjectionParams.y;

				return dist;
			}

			float4 Frag(Varyings i) : SV_Target
			{
				float2 uv = i.texcoordStereo.xy;

				float4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);

				float zsample = GetDepth(uv);
				float4 worldPos = GetWorldPositionFromDepth(uv);
				float4 cameraWorldPos = mul(unity_ObjectToWorld, worldPos);
				float3 cameraWorldDir = _WorldSpaceCameraPos.xyz - worldPos.xyz;

				float depth = Linear01Depth(zsample * (zsample < 1.0));
				float computedDistance = ComputeDistance(cameraWorldDir.rgb, depth);

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

				fog = lerp(fog, 0.0f, 1 - _Intensity);
				fog_height = lerp(fog_height, 0.0f, 1 - _Intensity);

				float4 cubemap = float4(0,0,0,0);
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

				color.rgb = lerp(color.rgb, cubemap.rgb, fog);
				color.rgb = lerp(color.rgb, cubemap.rgb, fog_height);

				if (DebugModes.x > 0) //view classic fog
					return float4(fog, fog, fog, 1.0);
				else if (DebugModes.y > 0) //view height fog
					return float4(fog_height, fog_height, fog_height, 1.0);
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
