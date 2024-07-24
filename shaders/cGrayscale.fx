
#include "shared/cShade.fxh"
#include "shared/cColor.fxh"

/*
    [Shader Options]
*/

uniform int _Select <
    ui_label = "Luminance Method";
    ui_type = "combo";
    ui_items = "Average\0Min\0Median\0Max\0Length\0Min+Max\0None\0";
> = 0;

/*
    [Pixel Shaders]
*/

float4 PS_Luminance(CShade_VS2PS_Quad Input) : SV_TARGET0
{
    float4 Color = tex2D(CShade_SampleColorTex, Input.Tex0);
    float4 OutputColor = CColor_GetLuma(Color, _Select);
    return OutputColor;
}

technique CShade_Grayscale
{
    pass
    {
        SRGBWriteEnable = WRITE_SRGB;

        VertexShader = CShade_VS_Quad;
        PixelShader = PS_Luminance;
    }
}
