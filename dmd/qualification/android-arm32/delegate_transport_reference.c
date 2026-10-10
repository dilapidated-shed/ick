struct DelegatePair
{
    void *context;
    void *function_pointer;
};

int c_delegate_register_reference(int lead, struct DelegatePair callback, int tail)
{
    return lead == 19 &&
           (unsigned long) callback.context == 17UL &&
           (unsigned long) callback.function_pointer == 34UL &&
           tail == 23 ? 42 : 1;
}

int c_delegate_stack_reference(int first, int second, int third, int fourth,
                               struct DelegatePair callback, int tail)
{
    return first == 1 && second == 2 && third == 3 && fourth == 4 &&
           (unsigned long) callback.context == 17UL &&
           (unsigned long) callback.function_pointer == 34UL &&
           tail == 23 ? 42 : 1;
}
