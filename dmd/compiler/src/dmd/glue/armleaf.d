/**
 * Admission boundary for the experimental Android AArch64 native leaf target.
 *
 * In particular, stock Mars' Linux extended-real model is not Android's
 * binary128 C long double ABI. Reject unqualified representations before the
 * native generator can silently emit them or assert on an unsupported width.
 * This gate does not replace AArch64 code generation with a Thumb generator.
 *
 * License: Boost License 1.0
 */
module dmd.glue.armleaf;

import dmd.arraytypes : Dsymbols;
import dmd.astenums : TY, STC, LINK, VarArg, FileType;
import dmd.declaration;
import dmd.dmodule;
import dmd.dsymbolsem : include;
import dmd.errors : error;
import dmd.expression;
import dmd.func;
import dmd.globals : global;
import dmd.init;
import dmd.location;
import dmd.mtype;
import dmd.statement;
import dmd.tokens : EXP;
import dmd.typesem : toBasetype;
import dmd.visitor : StoppableVisitor;
import dmd.visitor.postorder : walkPostorder;

private void diagnose(Loc loc, const(char)* detail)
{
    error(loc, "AArch64 Android leaf boundary: %s", detail);
}

private bool supported(Type type)
{
    if (!type) return true;
    switch (type.toBasetype().ty)
    {
        case TY.Tvoid: case TY.Tbool: case TY.Tuns8:
        case TY.Tint32: case TY.Tuns32:
        case TY.Tint64: case TY.Tuns64: case TY.Tpointer: case TY.Tfloat32:
            return true;
        default:
            return false;
    }
}

private void check_type(Type type, Loc loc)
{
    if (!supported(type))
        diagnose(loc, "only ubyte, integer, pointer and binary32 scalar representations are qualified; aggregates, double and real are not");
}

private bool abi_type(Type type)
{
    if (!type) return true;
    switch (type.toBasetype().ty)
    {
        case TY.Tvoid: case TY.Tbool: case TY.Tint32: case TY.Tuns32:
        case TY.Tint64: case TY.Tuns64: case TY.Tpointer: case TY.Tfloat32:
            return true;
        default:
            return false;
    }
}

private void check_abi_type(Type type, Loc loc)
{
    if (!abi_type(type))
        diagnose(loc, "external ABI positions remain limited to word-sized integer, pointer and binary32 scalar representations");
}

private void check_direct_c_function(FuncDeclaration function_, Loc loc)
{
    auto signature = function_.type.toTypeFunction();
    if (function_.resolvedLinkage() != LINK.c || function_.isNested() || function_.isMember() ||
        signature.isRef || signature.parameterList.varargs != VarArg.none ||
        (function_.parameters && function_.parameters.length > 4))
        diagnose(loc, "direct calls require top-level extern(C), non-variadic scalar functions with at most four arguments");

    check_abi_type(signature.next, loc);
    if (function_.parameters) foreach (parameter; *function_.parameters)
    {
        check_abi_type(parameter.type, parameter.loc);
        if (parameter.storage_class & (STC.ref_ | STC.out_ | STC.lazy_))
            diagnose(parameter.loc, "direct-call ref/out/lazy parameters are unqualified");
    }
}

private extern(C++) class Expressions : StoppableVisitor
{
    alias visit = typeof(super).visit;
    bool[VarDeclaration] locals;
    bool[const(void)*] directCallees;

    private extern(C++) class CallCollector : StoppableVisitor
    {
        alias visit = typeof(super).visit;
        Expressions owner;
        extern(D) this(Expressions owner) { this.owner = owner; }

        override void visit(Expression e)
        {
            if (auto call = e.isCallExp())
            {
                auto callee = call.e1 ? call.e1.isVarExp() : null;
                auto function_ = callee ? callee.var.isFuncDeclaration() : null;
                if (!function_)
                {
                    diagnose(e.loc, "only direct extern(C) function calls are qualified");
                    return;
                }
                owner.directCallees[cast(const(void)*)call.e1] = true;
            }
        }
    }

    void inspect(Expression expression_)
    {
        if (!expression_) return;
        auto collector = new CallCollector(this);
        walkPostorder(expression_, collector);
        walkPostorder(expression_, this);
    }

    void local(VarDeclaration declaration)
    {
        check_type(declaration.type, declaration.loc);
        if (declaration.storage_class & (STC.static_ | STC.ref_ | STC.out_ | STC.lazy_))
            diagnose(declaration.loc, "static/ref/out/lazy locals are unqualified");
        locals[declaration] = true;
        if (declaration._init)
        {
            if (auto initializer = declaration._init.isExpInitializer())
                inspect(initializer.exp);
            else
                diagnose(declaration.loc, "non-expression initialization is unqualified");
        }
    }

    override void visit(Expression e)
    {
        if (auto functionValue = e.isVarExp())
        {
            if (auto function_ = functionValue.var.isFuncDeclaration())
            {
                if (!(cast(const(void)*)e in directCallees))
                    diagnose(e.loc, "function values are unqualified; only direct calls are allowed");
                check_direct_c_function(function_, e.loc);
                return;
            }
        }

        check_type(e.type, e.loc);
        if (auto declaration = e.isDeclarationExp())
        {
            if (auto variable = declaration.declaration.isVarDeclaration()) local(variable);
            else diagnose(e.loc, "only scalar local declarations are qualified");
        }
        if (auto variable = e.isVarExp())
        {
            auto declaration = variable.var.isVarDeclaration();
            if (!declaration || !(declaration in locals))
                diagnose(e.loc, "external or captured values are unqualified");
        }
        switch (e.op)
        {
            case EXP.call:
            {
                auto call = e.isCallExp();
                auto callee = call.e1 ? call.e1.isVarExp() : null;
                auto function_ = callee ? callee.var.isFuncDeclaration() : null;
                if (!function_)
                {
                    diagnose(e.loc, "only direct extern(C) function calls are qualified");
                    break;
                }
                check_direct_c_function(function_, e.loc);
                break;
            }
            case EXP.new_: case EXP.newAnonymousClass:
            case EXP.arrayLiteral: case EXP.assocArrayLiteral: case EXP.structLiteral:
            case EXP.assert_: case EXP.throw_: case EXP.delegate_: case EXP.function_:
                diagnose(e.loc, "allocation, delegates and runtime operations are unqualified");
                break;
            default: break;
        }
    }
}

private extern(C++) class Statements : StoppableVisitor
{
    alias visit = typeof(super).visit;
    Expressions expressions;
    extern(D) this(Expressions expressions) { this.expressions = expressions; }

    override void visit(Statement s)
    {
        if (auto e = s.isExpStatement()) { expressions.inspect(e.exp); return; }
        if (auto r = s.isReturnStatement()) { expressions.inspect(r.exp); return; }
        if (auto b = s.isIfStatement()) { expressions.inspect(b.condition); return; }
        if (auto f = s.isForStatement())
        { expressions.inspect(f.condition); expressions.inspect(f.increment); return; }
        if (auto w = s.isWhileStatement()) { expressions.inspect(w.condition); return; }
        if (s.isCompoundStatement() || s.isCompoundDeclarationStatement() ||
            s.isScopeStatement() || s.isBreakStatement() || s.isContinueStatement() || s.isImportStatement())
            return;
        diagnose(s.loc, "statement is outside the scalar leaf qualification boundary");
    }
}

bool validate_aarch64_leaves(Module[] modules)
{
    const before = global.errors;
    void members(Dsymbols* symbols)
    {
        if (!symbols) return;
        foreach (symbol; *symbols)
        {
            if (auto attributes = symbol.isAttribDeclaration())
            { members(include(attributes, null)); continue; }
            if (auto function_ = symbol.isFuncDeclaration())
            {
                if (!function_.fbody) continue;
                auto signature = function_.type.toTypeFunction();
                if (function_.resolvedLinkage() != LINK.c || function_.isNested() || function_.isMember() ||
                    signature.isRef || signature.parameterList.varargs != VarArg.none ||
                    (function_.parameters && function_.parameters.length > 4))
                    diagnose(function_.loc, "requires top-level extern(C), non-variadic leaves with at most four arguments");
                check_abi_type(signature.next, function_.loc);
                auto expressions = new Expressions();
                if (function_.parameters) foreach (parameter; *function_.parameters)
                {
                    check_abi_type(parameter.type, parameter.loc);
                    if (parameter.storage_class & (STC.ref_ | STC.out_ | STC.lazy_))
                        diagnose(parameter.loc, "ref/out/lazy parameters are unqualified");
                    expressions.locals[parameter] = true;
                }
                auto statements = new Statements(expressions);
                walkPostorder(function_.fbody, statements);
                continue;
            }
            if (symbol.isImport() || symbol.isAliasDeclaration() ||
                symbol.isEnumDeclaration() || symbol.isStaticAssert()) continue;
            if (auto variable = symbol.isVarDeclaration())
                if (variable.storage_class & STC.manifest) continue;
            diagnose(symbol.loc, "global data and non-leaf declarations are unqualified");
        }
    }
    foreach (module_; modules)
        if (module_.filetype != FileType.dhdr) members(module_.members);
    if (global.errors != before)
    {
        foreach (module_; modules)
            if (module_.filetype != FileType.dhdr) module_.deleteObjFile();
        return false;
    }
    return true;
}
