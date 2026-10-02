alias float4 = __vector(float[4]);

extern(C) void fft_butterfly4(
    float* evenReal,
    float* evenImag,
    float* oddReal,
    float* oddImag,
    float* leftReal,
    float* leftImag,
    float* rightReal,
    float* rightImag,
    float* twiddleReal,
    float* twiddleImag)
{
    auto lr = *cast(float4*)leftReal;
    auto li = *cast(float4*)leftImag;
    auto rr = *cast(float4*)rightReal;
    auto ri = *cast(float4*)rightImag;
    auto wr = *cast(float4*)twiddleReal;
    auto wi = *cast(float4*)twiddleImag;

    auto productReal = rr * wr - ri * wi;
    auto productImag = rr * wi + ri * wr;

    *cast(float4*)evenReal = lr + productReal;
    *cast(float4*)evenImag = li + productImag;
    *cast(float4*)oddReal = lr - productReal;
    *cast(float4*)oddImag = li - productImag;
}
