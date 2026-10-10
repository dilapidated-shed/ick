module delegate_transport;

alias Callback = int delegate(int);

pragma(mangle, "delegate_transport_register_sink")
int delegateTransportRegisterSink(int lead, scope Callback callback, int tail);

pragma(mangle, "delegate_transport_register_forward")
int delegateTransportRegisterForward(int lead, scope Callback callback, int tail)
{
    return delegateTransportRegisterSink(lead, callback, tail);
}

pragma(mangle, "delegate_transport_stack_sink")
int delegateTransportStackSink(int first, int second, int third, int fourth,
                               scope Callback callback, int tail);

pragma(mangle, "delegate_transport_stack_forward")
int delegateTransportStackForward(int first, int second, int third, int fourth,
                                  scope Callback callback, int tail)
{
    return delegateTransportStackSink(first, second, third, fourth, callback, tail);
}
