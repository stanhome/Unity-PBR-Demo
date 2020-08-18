Shader "Unlit/PBR"
{
Properties
{
    //_MainTex ("Texture", 2D) = "white" {}
	_Albedo ("Albedo", color) = (1, 1, 1, 1)
	_Metallic ("Metallic", Range(0, 1)) = 0
	_Roughness ("Roughness", Range(0.01, 1)) = 0.05
	_AO ("AO", Range(0, 1)) = 1
	[Header(Lighting)]
	_PointLightPos("PointLightPos", vector) = (0, 0, 0, 1)
}

CGINCLUDE

#include "UnityCG.cginc"
#include "Lighting.cginc"
#include "UnityLightingCommon.cginc"

struct appdata
{
	float4 aPos : POSITION;
	float3 aNormal : Normal;
	float2 aTexCoords : TEXCOORD0;
};

struct v2f
{
	float4 vertex : SV_POSITION;
	float2 uv : TEXCOORD0;
	float3 worldPos : TEXCOORD1;
	float3 normal : TEXCOORD2;
};

sampler2D _MainTex;
float4 _MainTex_ST;

v2f vert (appdata v)
{
	v2f o;
	o.worldPos = mul(unity_ObjectToWorld, v.aPos);
	o.normal = UnityObjectToWorldNormal(v.aNormal);
	o.uv = TRANSFORM_TEX(v.aTexCoords, _MainTex);
	o.vertex = UnityObjectToClipPos(v.aPos);
	return o;
}

////////////////////////////////////
// PBR
uniform float3 _Albedo;
uniform float _Metallic;
uniform float _Roughness;
uniform float _AO;

uniform float3 _PointLightPos;

// normal distribution
float distributionGGX(float3 n, float3 h, float roughness)
{
	const float PI = 3.14159265359;

	//float a = roughness * roughness;
	float a = roughness;
	float a2 = a * a;
	float NdotH = max(dot(n, h), 0.0);
	float NdotH2 = NdotH * NdotH;

	float numerator = a2;
	float denominator = (NdotH2 * (a2 - 1.0) + 1.0);
	denominator = PI * denominator * denominator;

	return numerator / denominator;
}


// geometry function
float geometrySchlickGGX(float NdotV, float roughness)
{
	float r = (roughness + 1.0);
	float k = (r * r) / 8.0;

	float numerator = NdotV;
	float denominator = NdotV * (1 - k) + k;

	return numerator / denominator;
}
float geometrySmith(float3 n, float3 v, float3 l, float roughness)
{
	float NdotV = max(dot(n, v), 0.0);
	float NdotL = max(dot(n, l), 0.0);
	float ggx1 = geometrySchlickGGX(NdotV, roughness);
	float ggx2 = geometrySchlickGGX(NdotL, roughness);

	return ggx1 * ggx2;
}

// Fresnel
float3 fresnelSchlick(float cosTheta, float3 f0)
{
	return f0 + (1.0 - f0) * pow(1.0 - cosTheta, 5.0);
}

// Cook-Torrance BRDF
float3 BRDF(float3 n, float3 v, float3 l, float roughness, float metallic, float3 F0, float3 albedoColor) {
	float3 h = normalize(v + l);
	
	float NDF = distributionGGX(n, h, roughness);
	float G = geometrySmith(n, v, l, roughness);
	float3 F = fresnelSchlick(clamp(dot(v, n), 0.0, 1.0), F0);

	// diffuse term
	const float PI = 3.14159265359;
	float3 diffuse = albedoColor / PI;

	// specular term
	float3 numerator = NDF * G * F;
	float denominator = 4 * max(dot(n, v), 0.0) * max(dot(n, l), 0.0);
	float3 specular = numerator / max(denominator, 0.001);

	//ratio
	float3 kS = F; // kS is equal to Fresnel
	// for energy convervation, the diffuse and specular light can't be above 1.0(unless the surface emits light);
	// to preserve this relationship
	// the diffuse component(kD) should equal 1.0 - kS.
	float3 kD = float3(1.0, 1.0, 1.0) - kS;

	// multiply kD by the inverse metalness such that only non-metals have diffuse lighting.
	// or a linear blend if partly metal(pure metals have no diffuse light).
	kD *= (1.0 - metallic);

	// Note that we already multiplied the BRDF by the Fresnel(kS), so we won't multiply by kS again.
	return kD * diffuse + specular;
}

fixed4 frag (v2f i) : SV_Target
{
	float3 albedo = _Albedo;
	float metallic = _Metallic;
	float roughness = _Roughness;
	float ao = _AO;

	//Lighting Properties
	float3 lightPos0 = _PointLightPos;

	float3 n = normalize(i.normal);
	float3 v = normalize(_WorldSpaceCameraPos.xyz - i.worldPos);

	float3 f0 = float3(0.04, 0.04, 0.04);
	f0 = lerp(f0, albedo, metallic);

	// reflectance equation
	float3 Lo = float3(0, 0, 0);
	{
		float3 l = (lightPos0 - i.worldPos);
		float lightDistance = length(l);
		float attenuation = 1.0 / (lightDistance * lightDistance);
		float3 radiance = _LightColor0.rgb * attenuation * 100;

		// Cook-Torrance BRDF
		l = normalize(l);
		float3 BRDFVal = BRDF(n, v, l, roughness, metallic, f0, albedo);

		// scale light by NdotL
		float NdotL = max(dot(n, l), 0.0);

		Lo += BRDFVal * radiance * NdotL;
	}

	float3 ambient = float3(0.03, 0.03, 0.03) * albedo * ao;
	float3 col = ambient + Lo;
	
	// HDR tone mapping
	col = col / (col + float3(1.0, 1.0, 1.0));

	// gamma correct
	const float gammaPow = 1.0 / 2.2;
	col = pow(col, float3(gammaPow, gammaPow, gammaPow));

	return fixed4(col, 1.0);
}

ENDCG

SubShader
{
    Tags { "RenderType"="Opaque" }
    LOD 100

    Pass
    {
        CGPROGRAM
        #pragma vertex vert
        #pragma fragment frag
        ENDCG
    }
}
}
