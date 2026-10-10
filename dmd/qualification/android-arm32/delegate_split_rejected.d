module delegate_split_rejected;

alias Callback = int delegate(int);

pragma(mangle, "delegate_split_rejected")
int delegateSplitRejected(int first, int second, int third, scope Callback callback)
{
    return first + second + third;
}
