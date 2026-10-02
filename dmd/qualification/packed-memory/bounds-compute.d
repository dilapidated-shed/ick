module packed_memory_bounds_compute;

import icky.imprecise;
import icky.packed_memory;

nothrow @nogc:

extern(C) int main(int argc, char** argv)
{
    UE5M3[1] valid_left = [UE5M3.from_code(21)];
    E3M2[1] valid_right = [E3M2.from_code(7)];
    UE5M3[0] empty_left;
    E3M2[0] empty_right;

    if (argc < 2)
        return 98;
    switch (argv[1][0])
    {
        case 'e':
            compute_at!(Float16, "+")(empty_left[], 0, valid_right[], 0);
            break;
        case 'r':
            compute_at!(Float16, "+")(valid_left[], 0, empty_right[], 0);
            break;
        case 'b':
            compute_at!(Float16, "+")(empty_left[], 0, empty_right[], 0);
            break;
        case 'l':
            compute_at!(Float16, "+")(valid_left[], 1, valid_right[], 0);
            break;
        case 'R':
            compute_at!(Float16, "+")(valid_left[], 0, valid_right[], 1);
            break;
        case 'L':
            compute_at!(Float16, "+")(valid_left[], size_t.max, valid_right[], 0);
            break;
        case 'H':
            compute_at!(Float16, "+")(valid_left[], 0, valid_right[], size_t.max);
            break;
        default:
            return 97;
    }
    return 99;
}
