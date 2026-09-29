module gdc_thin_arrow_lambda_rejected;

extern(C) int probe()
{
    auto square = λ(int x) → x²;
    return square(3);
}
