#include <stdio.h>

#include <ick/imprecise.h>
#include <ick/circle.h>

typedef struct {
    unsigned long count;
    unsigned long skipped;
    float max_abs;
    float max_relative;
    float worst_input;
    float worst_reference;
    float worst_result;
} ResidualStats;

static float
abs_float(float value)
{
    return value < 0.0f ? -value : value;
}

static int
finite_float(float value)
{
    return (ick_float_bits(value) & 0x7f800000u) != 0x7f800000u;
}

static void
record_residual(ResidualStats *stats, float input, float reference, float result)
{
    float residual;
    float absolute;
    float denominator;
    float relative;

    if (!finite_float(reference) || !finite_float(result)) {
        ++stats->skipped;
        return;
    }

    residual = result - reference;
    absolute = abs_float(residual);
    denominator = abs_float(reference);
    relative = denominator == 0.0f ? absolute : absolute / denominator;

    ++stats->count;
    if (absolute > stats->max_abs) {
        stats->max_abs = absolute;
        stats->worst_input = input;
        stats->worst_reference = reference;
        stats->worst_result = result;
    }
    if (relative > stats->max_relative)
        stats->max_relative = relative;
}

static void
print_stats(const char *section, const char *format, const char *operation,
            const ResidualStats *stats)
{
    printf("summary,%s,%s,%s,count=%lu,skipped=%lu,max_abs=%.9g,"
           "max_relative=%.9g,worst_input=%.9g,worst_reference=%.9g,"
           "worst_result=%.9g,worst_residual=%.9g\n",
           section, format, operation,
           stats->count, stats->skipped, stats->max_abs, stats->max_relative,
           stats->worst_input, stats->worst_reference, stats->worst_result,
           stats->worst_result - stats->worst_reference);
}

static void
print_constructor_samples(void)
{
    static const float samples[] = {
        -100000.0f, -65520.0f, -57344.0f, -448.0f, -32.0f, -28.0f,
        -16.0f, -3.1415927f, -1.5f, -1.0f, -0.21875f, -0.09375f,
        -0.03125f, -0.0f, 0.0f, 0.03125f, 0.0625f, 0.09375f,
        0.15625f, 0.21875f, 0.33333334f, 0.5f, 1.0f, 1.5f,
        3.1415927f, 16.0f, 26.0f, 28.0f, 32.0f, 448.0f, 57344.0f,
        65504.0f, 65520.0f, 100000.0f
    };
    unsigned i;

    puts("section,constructor_samples");
    puts("sample,format,input,result,residual,code");

    for (i = 0; i < sizeof samples / sizeof samples[0]; ++i) {
        float input = samples[i];
        Float16 f16 = float16_from_float(input);
        E4M3 e4 = e4m3_from_float(input);
        E5M2 e52 = e5m2_from_float(input);
        E3M2 e32 = e3m2_from_float(input);
        E5M3 e53;
        float result;

        result = float16_to_float(f16);
        printf("sample,Float16,%.9g,%.9g,%.9g,0x%04x\n",
               input, result, result - input, (unsigned)float16_code(f16));

        result = e4m3_to_float(e4);
        printf("sample,E4M3,%.9g,%.9g,%.9g,0x%02x\n",
               input, result, result - input, (unsigned)e4m3_code(e4));

        result = e5m2_to_float(e52);
        printf("sample,E5M2,%.9g,%.9g,%.9g,0x%02x\n",
               input, result, result - input, (unsigned)e5m2_code(e52));

        result = e3m2_to_float(e32);
        printf("sample,E3M2,%.9g,%.9g,%.9g,0x%02x\n",
               input, result, result - input, (unsigned)e3m2_code(e32));

        if (e5m3_from_float(input, &e53)) {
            result = e5m3_to_float(e53);
            printf("sample,E5M3,%.9g,%.9g,%.9g,0x%02x\n",
                   input, result, result - input, (unsigned)e5m3_code(e53));
        } else {
            printf("sample,E5M3,%.9g,unsupported,unsupported,unsupported\n",
                   input);
        }
    }
}

static void
constructor_sweeps(void)
{
    static const ick_u32 mantissas[] = {
        0u, 1u, 0x000001u, 0x100000u, 0x3fffffu,
        0x400000u, 0x600000u, 0x7ffffeu, 0x7fffffu
    };
    ResidualStats f16 = {0}, e4 = {0}, e52 = {0}, e32 = {0}, e53 = {0};
    unsigned sign;
    unsigned exponent;
    unsigned m;

    for (sign = 0; sign < 2; ++sign) {
        for (exponent = 0; exponent < 255; ++exponent) {
            for (m = 0; m < sizeof mantissas / sizeof mantissas[0]; ++m) {
                ick_u32 bits = ((ick_u32)sign << 31)
                             | ((ick_u32)exponent << 23)
                             | mantissas[m];
                float input = ick_float_from_bits(bits);
                float magnitude = abs_float(input);
                float result;
                E5M3 encoded53;

                if (magnitude <= 65504.0f) {
                    result = float16_to_float(float16_from_float(input));
                    record_residual(&f16, input, input, result);
                }

                if (magnitude <= 448.0f) {
                    result = e4m3_to_float(e4m3_from_float(input));
                    record_residual(&e4, input, input, result);
                }

                if (magnitude <= 57344.0f) {
                    result = e5m2_to_float(e5m2_from_float(input));
                    record_residual(&e52, input, input, result);
                }

                if (magnitude <= 28.0f) {
                    result = e3m2_to_float(e3m2_from_float(input));
                    record_residual(&e32, input, input, result);
                }

                if (e5m3_from_float(input, &encoded53)) {
                    result = e5m3_to_float(encoded53);
                    record_residual(&e53, input, input, result);
                }
            }
        }
    }

    puts("section,constructor_sweeps");
    print_stats("constructor", "Float16", "encode_decode", &f16);
    print_stats("constructor", "E4M3", "encode_decode", &e4);
    print_stats("constructor", "E5M2", "encode_decode", &e52);
    print_stats("constructor", "E3M2", "encode_decode", &e32);
    print_stats("constructor", "E5M3", "encode_decode", &e53);
}

static void
e3m2_operation_sweep(void)
{
    ResidualStats add = {0}, sub = {0}, mul = {0}, div = {0};
    unsigned left, right;

    for (left = 0; left < 64; ++left) {
        for (right = 0; right < 64; ++right) {
            E3M2 a = e3m2_from_code((ick_byte)left);
            E3M2 b = e3m2_from_code((ick_byte)right);
            float af = e3m2_to_float(a);
            float bf = e3m2_to_float(b);
            float ref;

            ref = af + bf;
            record_residual(&add, af, ref, e3m2_to_float(e3m2_add(a, b)));
            ref = af - bf;
            record_residual(&sub, af, ref, e3m2_to_float(e3m2_subtract(a, b)));
            ref = af * bf;
            record_residual(&mul, af, ref, e3m2_to_float(e3m2_multiply(a, b)));
            ref = af / bf;
            record_residual(&div, af, ref, e3m2_to_float(e3m2_divide(a, b)));
        }
    }

    print_stats("operation", "E3M2", "add", &add);
    print_stats("operation", "E3M2", "subtract", &sub);
    print_stats("operation", "E3M2", "multiply", &mul);
    print_stats("operation", "E3M2", "divide", &div);
}

static void
e4m3_operation_sweep(void)
{
    ResidualStats add = {0}, sub = {0}, mul = {0}, div = {0};
    unsigned left, right;

    for (left = 0; left < 256; ++left) {
        for (right = 0; right < 256; ++right) {
            E4M3 a = e4m3_from_code((ick_byte)left);
            E4M3 b = e4m3_from_code((ick_byte)right);
            float af = e4m3_to_float(a);
            float bf = e4m3_to_float(b);
            float ref;

            if (!finite_float(af) || !finite_float(bf))
                continue;

            ref = af + bf;
            record_residual(&add, af, ref, e4m3_to_float(e4m3_add(a, b)));
            ref = af - bf;
            record_residual(&sub, af, ref, e4m3_to_float(e4m3_subtract(a, b)));
            ref = af * bf;
            record_residual(&mul, af, ref, e4m3_to_float(e4m3_multiply(a, b)));
            ref = af / bf;
            record_residual(&div, af, ref, e4m3_to_float(e4m3_divide(a, b)));
        }
    }

    print_stats("operation", "E4M3", "add", &add);
    print_stats("operation", "E4M3", "subtract", &sub);
    print_stats("operation", "E4M3", "multiply", &mul);
    print_stats("operation", "E4M3", "divide", &div);
}

static void
e5m2_operation_sweep(void)
{
    ResidualStats add = {0}, sub = {0}, mul = {0}, div = {0};
    unsigned left, right;

    for (left = 0; left < 256; ++left) {
        for (right = 0; right < 256; ++right) {
            E5M2 a = e5m2_from_code((ick_byte)left);
            E5M2 b = e5m2_from_code((ick_byte)right);
            float af = e5m2_to_float(a);
            float bf = e5m2_to_float(b);
            float ref;

            if (!finite_float(af) || !finite_float(bf))
                continue;

            ref = af + bf;
            record_residual(&add, af, ref, e5m2_to_float(e5m2_add(a, b)));
            ref = af - bf;
            record_residual(&sub, af, ref, e5m2_to_float(e5m2_subtract(a, b)));
            ref = af * bf;
            record_residual(&mul, af, ref, e5m2_to_float(e5m2_multiply(a, b)));
            ref = af / bf;
            record_residual(&div, af, ref, e5m2_to_float(e5m2_divide(a, b)));
        }
    }

    print_stats("operation", "E5M2", "add", &add);
    print_stats("operation", "E5M2", "subtract", &sub);
    print_stats("operation", "E5M2", "multiply", &mul);
    print_stats("operation", "E5M2", "divide", &div);
}

static void
float16_operation_sweep(void)
{
    ResidualStats add = {0}, sub = {0}, mul = {0}, div = {0};
    unsigned left, right;

    /* 257 is coprime to 65536, so this walks a broad deterministic subset of
       the binary16 code space rather than only one exponent neighborhood. */
    for (left = 0; left < 65536; left += 257) {
        for (right = 0; right < 65536; right += 257) {
            Float16 a = float16_from_code((ick_u16)left);
            Float16 b = float16_from_code((ick_u16)right);
            float af = float16_to_float(a);
            float bf = float16_to_float(b);
            float ref;

            if (!finite_float(af) || !finite_float(bf))
                continue;

            ref = af + bf;
            record_residual(&add, af, ref, float16_to_float(float16_add(a, b)));
            ref = af - bf;
            record_residual(&sub, af, ref, float16_to_float(float16_subtract(a, b)));
            ref = af * bf;
            record_residual(&mul, af, ref, float16_to_float(float16_multiply(a, b)));
            ref = af / bf;
            record_residual(&div, af, ref, float16_to_float(float16_divide(a, b)));
        }
    }

    print_stats("operation", "Float16", "add", &add);
    print_stats("operation", "Float16", "subtract", &sub);
    print_stats("operation", "Float16", "multiply", &mul);
    print_stats("operation", "Float16", "divide", &div);
}

static void
print_operation_samples(void)
{
    static const float pairs[][2] = {
        { 0.1f, 0.2f },
        { 0.33333334f, 0.66666669f },
        { 1.0f, 3.0f },
        { 1.5f, 0.25f },
        { 3.1415927f, 2.7182817f },
        { 15.0f, 0.0625f },
        { 24.0f, 4.0f },
        { 256.0f, 1.5f },
        { 32768.0f, 1.5f }
    };
    unsigned i;

    puts("section,operation_samples");
    puts("sample,format,operation,left,right,reference,result,residual");

    for (i = 0; i < sizeof pairs / sizeof pairs[0]; ++i) {
        float left = pairs[i][0], right = pairs[i][1];

#define PRINT_FOUR(FORMAT, TYPE, FROM, TO, ADD, SUB, MUL, DIV) do {             \
        TYPE a = FROM(left);                                                     \
        TYPE b = FROM(right);                                                    \
        float aq = TO(a), bq = TO(b);                                            \
        float reference = aq + bq;                                               \
        float result = TO(ADD(a, b));                                             \
        printf("sample," FORMAT ",add,%.9g,%.9g,%.9g,%.9g,%.9g\n",          \
               aq, bq, reference, result, result - reference);                   \
        reference = aq - bq;                                                     \
        result = TO(SUB(a, b));                                                   \
        printf("sample," FORMAT ",subtract,%.9g,%.9g,%.9g,%.9g,%.9g\n",     \
               aq, bq, reference, result, result - reference);                   \
        reference = aq * bq;                                                     \
        result = TO(MUL(a, b));                                                   \
        printf("sample," FORMAT ",multiply,%.9g,%.9g,%.9g,%.9g,%.9g\n",     \
               aq, bq, reference, result, result - reference);                   \
        reference = aq / bq;                                                     \
        result = TO(DIV(a, b));                                                   \
        printf("sample," FORMAT ",divide,%.9g,%.9g,%.9g,%.9g,%.9g\n",       \
               aq, bq, reference, result, result - reference);                   \
    } while (0)

        PRINT_FOUR("Float16", Float16, float16_from_float, float16_to_float,
                   float16_add, float16_subtract, float16_multiply, float16_divide);
        PRINT_FOUR("E4M3", E4M3, e4m3_from_float, e4m3_to_float,
                   e4m3_add, e4m3_subtract, e4m3_multiply, e4m3_divide);
        PRINT_FOUR("E5M2", E5M2, e5m2_from_float, e5m2_to_float,
                   e5m2_add, e5m2_subtract, e5m2_multiply, e5m2_divide);
        PRINT_FOUR("E3M2", E3M2, e3m2_from_float, e3m2_to_float,
                   e3m2_add, e3m2_subtract, e3m2_multiply, e3m2_divide);

#undef PRINT_FOUR
    }
}

static void
circle_residuals(void)
{
    long operation_cases = 0;
    long operation_nonzero = 0;
    int worst_tick_residual = 0;
    int point, amount, reflection;
    float worst_degree_residual = 0.0f;
    int worst_half_degree = 0;
    int half_degree;

    for (point = 0; point < 96; ++point) {
        for (amount = 0; amount < 96; ++amount) {
            Circle96 got = rotate96(rotation96(amount), circle96(point));
            int expected = (point + amount) % 96;
            int residual = (int)circle96_code(got) - expected;
            ++operation_cases;
            if (residual != 0)
                ++operation_nonzero;
            if (residual < 0 ? -residual > worst_tick_residual
                             : residual > worst_tick_residual)
                worst_tick_residual = residual < 0 ? -residual : residual;
        }

        for (reflection = 0; reflection < 96; ++reflection) {
            Circle96 got = reflect96(reflection96(reflection), circle96(point));
            int expected = reflection - point;
            int residual;
            if (expected < 0)
                expected += 96;
            residual = (int)circle96_code(got) - expected;
            ++operation_cases;
            if (residual != 0)
                ++operation_nonzero;
            if (residual < 0 ? -residual > worst_tick_residual
                             : residual > worst_tick_residual)
                worst_tick_residual = residual < 0 ? -residual : residual;
        }
    }

    /* Half-degree requests give a dense readable grid against the 3.75-degree
       Circle96 tick. Integer arithmetic picks the nearest tick; no residual
       size is treated as failure. */
    for (half_degree = 0; half_degree < 720; ++half_degree) {
        int numerator = half_degree * 2;
        int tick = (numerator + 7) / 15;
        float requested = (float)half_degree * 0.5f;
        float represented;
        float residual;

        if (tick == 96)
            tick = 0;
        represented = (float)tick * 3.75f;
        if (represented - requested > 180.0f)
            represented -= 360.0f;
        if (requested - represented > 180.0f)
            represented += 360.0f;
        residual = represented - requested;

        if (abs_float(residual) > abs_float(worst_degree_residual)) {
            worst_degree_residual = residual;
            worst_half_degree = half_degree;
        }
    }

    puts("section,circle96");
    printf("summary,circle96,exact_operations,cases=%ld,nonzero_tick_residuals=%ld,"
           "max_abs_tick_residual=%d\n",
           operation_cases, operation_nonzero, worst_tick_residual);
    printf("summary,circle96,half_degree_quantization,samples=720,"
           "max_abs_degree_residual=%.9g,worst_requested_degrees=%.9g,"
           "worst_residual_degrees=%.9g\n",
           abs_float(worst_degree_residual),
           (float)worst_half_degree * 0.5f,
           worst_degree_residual);

    printf("sample,circle96,one_flat,requested_degrees=60,"
           "ticks=%u,result_degrees=%.9g,residual_degrees=%.9g\n",
           (unsigned)rotation96_code(one_flat96()),
           (float)rotation96_code(one_flat96()) * 3.75f,
           (float)rotation96_code(one_flat96()) * 3.75f - 60.0f);
    printf("sample,circle96,one_third,requested_degrees=120,"
           "ticks=%u,result_degrees=%.9g,residual_degrees=%.9g\n",
           (unsigned)rotation96_code(one_third_turn96()),
           (float)rotation96_code(one_third_turn96()) * 3.75f,
           (float)rotation96_code(one_third_turn96()) * 3.75f - 120.0f);
}

int
main(void)
{
    puts("ick_residual_report_v1");
    puts("residual_convention=result-reference");
    puts("residual_magnitude_is_diagnostic_not_pass_fail");

    print_constructor_samples();
    constructor_sweeps();

    puts("section,operation_sweeps");
    float16_operation_sweep();
    e4m3_operation_sweep();
    e5m2_operation_sweep();
    e3m2_operation_sweep();
    print_operation_samples();

    circle_residuals();

    puts("report_complete");
    return ferror(stdout) ? 1 : 0;
}
