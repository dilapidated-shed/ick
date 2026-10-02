alias float4 = __vector(float[4]);

private float4 load4(float* source)
{
    return *cast(float4*)source;
}

private void store4(float* destination, float4 value)
{
    *cast(float4*)destination = value;
}

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
    auto lr = load4(leftReal);
    auto li = load4(leftImag);
    auto rr = load4(rightReal);
    auto ri = load4(rightImag);
    auto wr = load4(twiddleReal);
    auto wi = load4(twiddleImag);

    auto productReal = rr * wr - ri * wi;
    auto productImag = rr * wi + ri * wr;

    store4(evenReal, lr + productReal);
    store4(evenImag, li + productImag);
    store4(oddReal, lr - productReal);
    store4(oddImag, li - productImag);
}
