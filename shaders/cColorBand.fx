
/*
    [Shader Options]
*/

uniform int2 _Resolution <
    ui_label = "Resolution";
    ui_type = "slider";
    ui_min = 16;
    ui_max = 256;
> = int2(128, 128);

uniform int3 _Range <
    ui_label = "Color Band Range";
    ui_type = "slider";
    ui_min = 1.0;
    ui_max = 32.0;
> = 8;

uniform int _DitherMethod <
    ui_label = "Dither Method";
    ui_type = "combo";
    ui_items = "None\0Hash\0Interleaved Gradient Noise\0";
> = 0;

#include "shared/cProcedural.fxh"

#include "shared/cShade.fxh"
#include "shared/cBlend.fxh"

/*
    [Pixel Shaders]
*/

float4 PS_Color(CShade_VS2PS_Quad Input) : SV_TARGET0
{
    float2 ColorMapTex = floor(Input.Tex0 * _Resolution) / _Resolution;
    float4 ColorMap = tex2D(CShade_SampleGammaTex, ColorMapTex);

    float2 HashTex = floor(Input.Tex0 * _Resolution);
    float3 Dither = 0.0;

    switch (_DitherMethod)
    {
        case 0:
            Dither = 0.0;
            break;
        case 1:
            Dither = CProcedural_GetHash1(HashTex, 0.0) / _Range;
            break;
        case 2:
            Dither = CProcedural_GetInterleavedGradientNoise(HashTex) / _Range;
            break;
        default:
            Dither = 0.0;
            break;
    }

    // Color quantization
    ColorMap.rgb += (Dither / _Range);
    ColorMap.rgb = floor(ColorMap.rgb * _Range) / _Range;

    return CBlend_OutputChannels(float4(ColorMap.rgb, _CShadeAlphaFactor));
}

technique CShade_ColorBand
{
    pass
    {
        CBLEND_CREATE_STATES()

        VertexShader = CShade_VS_Quad;
        PixelShader = PS_Color;
    }
}
