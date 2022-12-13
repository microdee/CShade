
#if !defined(CVIDEOPROCESSING_FXH)
    #define CVIDEOPROCESSING_FXH

    #include "cMacros.fxh"
    #include "cGraphics.fxh"

    // Lucas-Kanade optical flow with bilinear fetches

    /*
        Calculate Lucas-Kanade optical flow by solving (A^-1 * B)
        [A11 A12]^-1 [-B1] -> [ A11 -A12] [-B1]
        [A21 A22]^-1 [-B2] -> [-A21  A22] [-B2]
        A11 = Ix^2
        A12 = IxIy
        A21 = IxIy
        A22 = Iy^2
        B1 = IxIt
        B2 = IyIt
    */

    struct Texel
    {
        float2 Size;
        float2 LOD;
    };

    struct UnpackedTex
    {
        float4 Tex;
        float4 WarpedTex;
    };

    void UnpackTex(in Texel Tx, in float4 Tex, in float2 Vectors, out UnpackedTex Output[3])
    {
        // Calculate texture attributes of each packed column of tex
        float4 WarpPackedTex = 0.0;
        // Warp horizontal texture coordinates with horizontal motion vector
        WarpPackedTex.x = Tex.x + (Vectors.x * abs(Tx.Size.x));
        // Warp vertical texture coordinates with vertical motion vector
        WarpPackedTex.yzw = Tex.yzw + (Vectors.yyy * abs(Tx.Size.yyy));

        // Unpack and assemble the column's texture coordinates
        // Outputs float4(Tex, 0.0, LOD) in 1 MAD
        const float4 TexMask = float4(1.0, 1.0, 0.0, 0.0);
        Output[0].Tex = (Tex.xyyy * TexMask) + Tx.LOD.xxxy;
        Output[1].Tex = (Tex.xzzz * TexMask) + Tx.LOD.xxxy;
        Output[2].Tex = (Tex.xwww * TexMask) + Tx.LOD.xxxy;

        Output[0].WarpedTex = (WarpPackedTex.xyyy * TexMask) + Tx.LOD.xxxy;
        Output[1].WarpedTex = (WarpPackedTex.xzzz * TexMask) + Tx.LOD.xxxy;
        Output[2].WarpedTex = (WarpPackedTex.xwww * TexMask) + Tx.LOD.xxxy;
    }

    // [-1,1] -> [DestSize.x, DestSize.y]
    float2 DecodeVectors(float2 Vectors, float2 ImgSize)
    {
        return Vectors * ImgSize;
    }

    // [DestSize.x, DestSize.y] -> [-1,1]
    float2 EncodeVectors(float2 Vectors, float2 ImgSize)
    {
        return clamp(Vectors / ImgSize, -1.0, 1.0);
    }

    float2 GetEigenValue(float3 G)
    {
        // A.x = A11; A.y = A22; A.z = A12/A22
        float A = (G.x + G.y) * 0.5;
        float B = sqrt((4.0 * (G.z * G.z)) + pow(G.x - G.y, 2.0)) * 0.5;
        return float2(A + B, A - B);
    }

    float2 GetPixelPyLK
    (
        float2 MainTex,
        float2 Vectors,
        sampler2D SampleG,
        sampler2D SampleI0,
        sampler2D SampleI1,
        bool CoarseLevel
    )
    {
        // Setup constants
        const int WindowSize = 9;
        const float EThreshold = 0.0001;

        // Initialize variables
        float3 A = 0.0;
        float2 B = 0.0;
        float2 E = 0.0;
        float4 G[WindowSize];
        float Determinant = 0.0;
        float2 MVectors = 0.0;
        bool Refine = false;

        // Calculate main texel information (TexelSize, TexelLOD)
        Texel Tx;
        float2 Ix = ddx(MainTex);
        float2 Iy = ddy(MainTex);
        float2 DPX = dot(Ix, Ix);
        float2 DPY = dot(Iy, Iy);
        Tx.Size.x = Ix.x;
        Tx.Size.y = Iy.y;
        // log2(x^n) = n*log2(x)
        Tx.LOD = float2(0.0, 0.5) * log2(max(DPX, DPY));
        float2 InvTexSize = 1.0 / abs(Tx.Size);

        // Decode written vectors from coarser level
        Vectors = DecodeVectors(Vectors, InvTexSize * 0.5);

        // The spatial(S) and temporal(T) derivative neighbors to sample
        UnpackedTex TexA[3];
        UnpackTex(Tx, MainTex.xyyy + (float4(-1.0, 1.0, 0.0, -1.0) * abs(Tx.Size.xyyy)), Vectors, TexA);

        UnpackedTex TexB[3];
        UnpackTex(Tx, MainTex.xyyy + (float4( 0.0, 1.0, 0.0, -1.0) * abs(Tx.Size.xyyy)), Vectors, TexB);

        UnpackedTex TexC[3];
        UnpackTex(Tx, MainTex.xyyy + (float4( 1.0, 1.0, 0.0, -1.0) * abs(Tx.Size.xyyy)), Vectors, TexC);

        UnpackedTex Pixel[WindowSize] =
        {
            TexA[0], TexA[1], TexA[2],
            TexB[0], TexB[1], TexB[2],
            TexC[0], TexC[1], TexC[2],
        };

        // Sum gradient matrix
        [unroll]
        for(int i = 0; i < WindowSize; i++)
        {
            G[i] = tex2Dlod(SampleG, Pixel[i].Tex);
            // A.x = A11; A.y = A22; A.z = A12/A22
            A.xyz += (G[i].xzx * G[i].xzz);
            A.xyz += (G[i].ywy * G[i].yww);
        }

        E = GetEigenValue(A);

        if(CoarseLevel == true)
        {
            Refine = true;
        }
        else if(min(E[0], E[1]) > EThreshold)
        {
            Refine = true;
        }
        else
        {
            Refine = false;
        }

        // Calculate optical flow
        [branch]
        if(Refine)
        {
            [unroll]
            for(int i = 0; i < WindowSize; i++)
            {
                float2 I0 = tex2Dlod(SampleI1, Pixel[i].WarpedTex).rg;
                float2 I1 = tex2Dlod(SampleI0, Pixel[i].Tex).rg;
                float2 IT = I0 - I1;

                // B.x = B1; B.y = B2
                B.xy += (G[i].xz * IT.rr);
                B.xy += (G[i].yw * IT.gg);
            }

            // Create -IxIy (A12) for A^-1 and its determinant
            A.z = -A.z;

            // Make determinant non-zero
            A.xy = A.xy + FP16_SMALLEST_SUBNORMAL;

            // Calculate A^-1 determinant
            Determinant = ((A.x * A.y) - (A.z * A.z));

            // Solve A^-1
            A = A / Determinant;

            // Calculate Lucas-Kanade matrix
            MVectors = mul(-B.xy, float2x2(A.yzzx));
            MVectors = (Determinant != 0.0) ? MVectors : 0.0;
        }

        // Propagate and encode vectors
        MVectors = EncodeVectors(Vectors + MVectors, InvTexSize);
        return MVectors;
    }
#endif
