
/*
    This is free and unencumbered software released into the public domain.

    Anyone is free to copy, modify, publish, use, compile, sell, or
    distribute this software, either in source code form or as a compiled
    binary, for any purpose, commercial or non-commercial, and by any
    means.

    In jurisdictions that recognize copyright laws, the author or authors
    of this software dedicate any and all copyright interest in the
    software to the public domain. We make this dedication for the benefit
    of the public at large and to the detriment of our heirs and
    successors. We intend this dedication to be an overt act of
    relinquishment in perpetuity of all present and future rights to this
    software under copyright law.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
    OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
    ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
    OTHER DEALINGS IN THE SOFTWARE.

    For more information, please refer to <http://unlicense.org/>
*/

#define __DEFAULT_TEXTURE_FORMAT RG16F
#include "ReferrerMacroScheme.fxh"

#define __EXTERNAL_MAGIC_SCALE -70000

#define Declare_InternalVelocity() CREATE_TEXTURE(OFlowTex, BUFFER_SIZE_2, RG16F, 1)
#define Use_InternalVelocity() OFlowTex
#define MagicScale_InternalVelocity() 1
#define OFlowPass_InternalVelocity() 1

#define Declare_LaunchPad() Declare_NamespaceTexture(Deferred, MotionVectorsTex)
#define Use_LaunchPad() Use_NamespaceTexture(Deferred, MotionVectorsTex)
#define MagicScale_LaunchPad() __EXTERNAL_MAGIC_SCALE
#define OFlowPass_LaunchPad() 0

#define Declare_LaunchPad_Old() Declare_NamespaceTexture(Velocity, OldMotionVectorsTex)
#define Use_LaunchPad_Old() Use_NamespaceTexture(Velocity, OldMotionVectorsTex)
#define MagicScale_LaunchPad_Old() __EXTERNAL_MAGIC_SCALE
#define OFlowPass_LaunchPad_Old() 0

#define Declare_Retained() Declare_Texture(texRetainedVelocity)
#define Use_Retained() texRetainedVelocity
#define MagicScale_Retained() __EXTERNAL_MAGIC_SCALE
#define OFlowPass_Retained() 0

#define MagicScale_Texture(name) __EXTERNAL_MAGIC_SCALE
#define OFlowPass_Texture() 0

#define MagicScale_NamespaceTexture(ns, name) __EXTERNAL_MAGIC_SCALE
#define OFlowPass_NamespaceTexture() 0

#ifndef VELOCITY_TEXTURE
#define VELOCITY_TEXTURE InternalVelocity()
#endif

#define OFlowFiltered_InternalVelocity() TempTex2b_RG16F
#define OFlowFiltered_LaunchPad() Use_LaunchPad()
#define OFlowFiltered_LaunchPad_Old() Use_LaunchPad_Old()
#define OFlowFiltered_Retained() Use_Retained()
#define OFlowFiltered_Texture(name) Use_Texture(name)
#define OFlowFiltered_NamespaceTexture(ns, name) Use_NamespaceTexture(ns, name)

/*
    [Shader Options]
*/

#include "shared/cColor.fxh"
#include "shared/cBlur.fxh"
#include "shared/cMotionEstimation.fxh"

uniform float _Time < source = "timer"; >;

uniform float _MipBias <
    ui_category = "Optical Flow";
    ui_label = "Mipmap Bias";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 7.0;
> = 0.0;

uniform float _BlendFactor <
    ui_category = "Optical Flow";
    ui_label = "Temporal Blending Factor";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 0.9;
> = 0.25;

uniform int _BlockSize <
    ui_category = "Datamosh";
    ui_label = "Block Size";
    ui_type = "slider";
    ui_min = 0;
    ui_max = 32;
> = 4;

uniform float _Entropy <
    ui_category = "Datamosh";
    ui_label = "Entropy";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.1;

uniform float _Contrast <
    ui_category = "Datamosh";
    ui_label = "Noise Contrast";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 4.0;
> = 0.1;

uniform float _Scale <
    ui_category = "Datamosh";
    ui_label = "Velocity Scale";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 2.0;
> = 1.0;

uniform float _Diffusion <
    ui_category = "Datamosh";
    ui_label = "Amount of Random Displacement";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 4.0;
> = 2.0;

#include "shared/cShade.fxh"
#include "shared/cBlend.fxh"

#ifndef LINEAR_SAMPLING
    #define LINEAR_SAMPLING 0
#endif

#if LINEAR_SAMPLING == 1
    #define FILTERING LINEAR
#else
    #define FILTERING POINT
#endif

/*
    [Textures and samplers]
*/

CREATE_TEXTURE_POOLED(TempTex1_RG8, BUFFER_SIZE_1, RG8, 3)
CREATE_TEXTURE_POOLED(TempTex2a_RG16F, BUFFER_SIZE_2, RG16F, 8)
CREATE_TEXTURE_POOLED(TempTex2b_RG16F, BUFFER_SIZE_2, RG16F, 8)
CREATE_TEXTURE_POOLED(TempTex3_RG16F, BUFFER_SIZE_3, RG16F, 1)
CREATE_TEXTURE_POOLED(TempTex4_RG16F, BUFFER_SIZE_4, RG16F, 1)
CREATE_TEXTURE_POOLED(TempTex5_RG16F, BUFFER_SIZE_5, RG16F, 1)

CREATE_SAMPLER(SampleTempTex1, TempTex1_RG8, LINEAR, MIRROR, MIRROR, MIRROR)
CREATE_SAMPLER(SampleTempTex2a, TempTex2a_RG16F, LINEAR, MIRROR, MIRROR, MIRROR)
CREATE_SAMPLER(SampleTempTex2b, TempTex2b_RG16F, LINEAR, MIRROR, MIRROR, MIRROR)
CREATE_SAMPLER(SampleTempTex3, TempTex3_RG16F, LINEAR, MIRROR, MIRROR, MIRROR)
CREATE_SAMPLER(SampleTempTex4, TempTex4_RG16F, LINEAR, MIRROR, MIRROR, MIRROR)
CREATE_SAMPLER(SampleTempTex5, TempTex5_RG16F, LINEAR, MIRROR, MIRROR, MIRROR)

CREATE_TEXTURE(Tex2c, BUFFER_SIZE_2, RG16F, 8)
CREATE_SAMPLER(SampleTex2c, Tex2c, LINEAR, MIRROR, MIRROR, MIRROR)

REFERRER(Declare, VELOCITY_TEXTURE)
CREATE_SAMPLER(SampleOFlowTex, REFERRER(Use, VELOCITY_TEXTURE), LINEAR, MIRROR, MIRROR, MIRROR)
CREATE_SAMPLER(SampleFilteredFlowTex, REFERRER(OFlowFiltered, VELOCITY_TEXTURE), FILTERING, MIRROR, MIRROR, MIRROR)

CREATE_TEXTURE(AccumTex, BUFFER_SIZE_0, R16F, 1)
CREATE_SAMPLER(SampleAccumTex, AccumTex, FILTERING, MIRROR, MIRROR, MIRROR)

CREATE_TEXTURE(FeedbackTex, BUFFER_SIZE_0, RGBA8, 1)
CREATE_SRGB_SAMPLER(SampleFeedbackTex, FeedbackTex, LINEAR, MIRROR, MIRROR, MIRROR)

float2 GetMotionVectors(float2 uv, float mipMap)
{
    return tex2Dlod(SampleFilteredFlowTex, float4(uv, 0.0, _MipBias)).xy * REFERRER(MagicScale, VELOCITY_TEXTURE);
}

float2 GetMotionVectorsLinear(float2 uv, float mipMap)
{
    return tex2Dlod(SampleOFlowTex, float4(uv, 0.0, _MipBias)).xy * REFERRER(MagicScale, VELOCITY_TEXTURE);
}

/*
    [Pixel Shaders]
*/

float2 PS_Normalize(CShade_VS2PS_Quad Input) : SV_TARGET0
{
    float3 Color = tex2D(CShade_SampleColorTex, Input.Tex0).rgb;
    return CColor_GetSphericalRG(Color).xy;
}

float2 PS_PrefilterHBlur(CShade_VS2PS_Quad Input) : SV_TARGET0
{
    return CBlur_GetPixelBlur(Input.Tex0, SampleTempTex1, true).rg;
}

float2 PS_PrefilterVBlur(CShade_VS2PS_Quad Input) : SV_TARGET0
{
    return CBlur_GetPixelBlur(Input.Tex0, SampleTempTex2a, false).rg;
}

float2 PS_LucasKanade4(CShade_VS2PS_Quad Input) : SV_TARGET0
{
    float2 Vectors = 0.0;
    return CMotionEstimation_GetPixelPyLK(Input.Tex0, Vectors, SampleTex2c, SampleTempTex2b);
}

float2 PS_LucasKanade3(CShade_VS2PS_Quad Input) : SV_TARGET0
{
    float2 Vectors = tex2D(SampleTempTex5, Input.Tex0).xy;
    return CMotionEstimation_GetPixelPyLK(Input.Tex0, Vectors, SampleTex2c, SampleTempTex2b);
}

float2 PS_LucasKanade2(CShade_VS2PS_Quad Input) : SV_TARGET0
{
    float2 Vectors = tex2D(SampleTempTex4, Input.Tex0).xy;
    return CMotionEstimation_GetPixelPyLK(Input.Tex0, Vectors, SampleTex2c, SampleTempTex2b);
}

float4 PS_LucasKanade1(CShade_VS2PS_Quad Input) : SV_TARGET0
{
    float2 Vectors = tex2D(SampleTempTex3, Input.Tex0).xy;
    return float4(CMotionEstimation_GetPixelPyLK(Input.Tex0, Vectors, SampleTex2c, SampleTempTex2b), 0.0, _BlendFactor);
}

// NOTE: We use MRT to immeduately copy the current blurred frame for the next frame
float4 PS_PostfilterHBlur(CShade_VS2PS_Quad Input, out float4 Copy : SV_TARGET0) : SV_TARGET1
{
    Copy = tex2D(SampleTempTex2b, Input.Tex0.xy);
    return float4(CBlur_GetPixelBlur(Input.Tex0, SampleOFlowTex, true).rg * REFERRER(MagicScale, VELOCITY_TEXTURE), 0.0, 1.0);
}

float4 PS_PostfilterVBlur(CShade_VS2PS_Quad Input) : SV_TARGET0
{
    return float4(CBlur_GetPixelBlur(Input.Tex0, SampleTempTex2a, false).rg, 0.0, 1.0);
}

// Datamosh

float RandUV(float2 Tex)
{
    float f = dot(float2(12.9898, 78.233), Tex);
    return frac(43758.5453 * sin(f));
}

float2 GetMVBlocks(float2 MV, float2 Tex, out float3 Random)
{
    float2 TexSize = fwidth(Tex);
    float2 Time = float2(_Time, 0.0);

    // Random numbers
    Random.x = RandUV(Tex.xy + Time.xy);
    Random.y = RandUV(Tex.xy + Time.yx);
    Random.z = RandUV(Tex.yx - Time.xx);

    // Normalized screen space -> Pixel coordinates
    MV = CMotionEstimation_UnnormalizeMotionVectors(MV * _Scale, TexSize);

    // Small random displacement (diffusion)
    MV += (Random.xy - 0.5)  * _Diffusion;

    // Pixel perfect snapping
    return round(MV);
}

float4 PS_Accumulate(CShade_VS2PS_Quad Input) : SV_TARGET0
{
    float Quality = 1.0 - _Entropy;
    float3 Random = 0.0;

    // Motion vectors
    float2 MV = GetMotionVectors(Input.Tex0, _MipBias);
    MV = CMotionEstimation_UnpackMotionVectors(MV);

    // Get motion blocks
    MV = GetMVBlocks(MV, Input.Tex0, Random);

    // Accumulates the amount of motion.
    float MVLength = length(MV);

    float4 OutputColor = 0.0;

    // Simple update
    float UpdateAcc = min(MVLength, _BlockSize) * 0.005;
    UpdateAcc += lerp(-Random.z, Random.z, Quality * 0.02);

    // Reset to random level
    float ResetAcc = (Random.z * 0.5) + Quality;

    // Reset if the amount of motion is larger than the block size.
    [branch]
    if(MVLength > _BlockSize)
    {
        OutputColor = float4((float3)ResetAcc, 0.0);
    }
    else
    {
        OutputColor = float4((float3)UpdateAcc, 1.0);
    }

    return OutputColor;
}

float4 PS_Datamosh(CShade_VS2PS_Quad Input) : SV_TARGET0
{
    float2 TexSize = fwidth(Input.Tex0);
    const float2 DisplacementTexel = BUFFER_SIZE_0;
    const float Quality = 1.0 - _Entropy;
    float3 Random = 0.0;

    // Motion vectors
    float2 MV = CMotionEstimation_UnpackMotionVectors(GetMotionVectors(Input.Tex0, _MipBias));

    // Get motion blocks
    MV = GetMVBlocks(MV, Input.Tex0, Random);

    // Get random motion
    float RandomMotion = RandUV(Input.Tex0 + length(MV));

    // Pixel coordinates -> Normalized screen space
    MV = CMotionEstimation_NormalizeMotionVectors(MV, TexSize);

    // Color from the original image
    float4 Source = tex2D(CShade_SampleColorTex, Input.Tex0);

    // Displacement vector
    float Disp = tex2D(SampleAccumTex, Input.Tex0).r;
    float4 Work = tex2D(SampleFeedbackTex, Input.Tex0 - MV);

    // Generate some pseudo random numbers.
    float4 Rand = frac(float4(1.0, 17.37135, 841.4272, 3305.121) * RandomMotion);

    // Generate noise patterns that look like DCT bases.
    float2 Frequency = Input.HPos.xy * (Rand.x * 80.0 / _Contrast);

    // Basis wave (vertical or horizontal)
    float DCT = cos(lerp(Frequency.x, Frequency.y, 0.5 < Rand.y));

    // Random amplitude (the high freq, the less amp)
    DCT *= Rand.z * (1.0 - Rand.x) * _Contrast;

    // Conditional weighting
    // DCT-ish noise: acc > 0.5
    float CW = (Disp > 0.5) * DCT;
    // Original image: rand < (Q * 0.8 + 0.2) && acc == 1.0
    CW = lerp(CW, 1.0, Rand.w < lerp(0.2, 1.0, Quality) * (Disp > (1.0 - 1e-3)));

    // If the conditions above are not met, choose work.
    return CBlend_OutputChannels(float4(lerp(Work.rgb, Source.rgb, CW), _CShadeAlphaFactor));
}

float4 PS_CopyColorTex(CShade_VS2PS_Quad Input) : SV_TARGET0
{
    return tex2D(CShade_SampleColorTex, Input.Tex0);
}

#define CREATE_PASS(VERTEX_SHADER, PIXEL_SHADER, RENDER_TARGET) \
    pass \
    { \
        VertexShader = VERTEX_SHADER; \
        PixelShader = PIXEL_SHADER; \
        RenderTarget0 = RENDER_TARGET; \
    }

technique CShade_KinoDatamosh
{
    // Normalize current frame
    CREATE_PASS(CShade_VS_Quad, PS_Normalize, TempTex1_RG8)

    // Prefilter blur
    CREATE_PASS(CShade_VS_Quad, PS_PrefilterHBlur, TempTex2a_RG16F)
    CREATE_PASS(CShade_VS_Quad, PS_PrefilterVBlur, TempTex2b_RG16F)

    // Bilinear Lucas-Kanade Optical Flow
    CREATE_PASS(CShade_VS_Quad, PS_LucasKanade4, TempTex5_RG16F)
    CREATE_PASS(CShade_VS_Quad, PS_LucasKanade3, TempTex4_RG16F)
    CREATE_PASS(CShade_VS_Quad, PS_LucasKanade2, TempTex3_RG16F)
    
#if REFERRER(OFlowPass, VELOCITY_TEXTURE)
    pass GetFineOpticalFlow
    {
        ClearRenderTargets = FALSE;
        BlendEnable = TRUE;
        BlendOp = ADD;
        SrcBlend = INVSRCALPHA;
        DestBlend = SRCALPHA;

        VertexShader = CShade_VS_Quad;
        PixelShader = PS_LucasKanade1;
        RenderTarget0 = OFlowTex;
    }
#endif
    // Postfilter blur
    pass MRT_CopyAndBlur
    {
        VertexShader = CShade_VS_Quad;
        PixelShader = PS_PostfilterHBlur;
        RenderTarget0 = Tex2c;
        RenderTarget1 = TempTex2a_RG16F;
    }

    pass
    {
        VertexShader = CShade_VS_Quad;
        PixelShader = PS_PostfilterVBlur;
        RenderTarget0 = TempTex2b_RG16F;
    }

    // Datamoshing
    pass
    {
        ClearRenderTargets = FALSE;
        BlendEnable = TRUE;
        BlendOp = ADD;
        SrcBlend = ONE;
        DestBlend = SRCALPHA; // The result about to accumulate

        VertexShader = CShade_VS_Quad;
        PixelShader = PS_Accumulate;
        RenderTarget0 = AccumTex;
    }

    pass
    {
        SRGBWriteEnable = WRITE_SRGB;
        CBLEND_CREATE_STATES()

        VertexShader = CShade_VS_Quad;
        PixelShader = PS_Datamosh;
    }

    // Copy frame for feedback
    pass
    {
        SRGBWriteEnable = WRITE_SRGB;

        VertexShader = CShade_VS_Quad;
        PixelShader = PS_CopyColorTex;
        RenderTarget0 = FeedbackTex;
    }
}
