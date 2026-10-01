/**
 * Typed DMD AST -> ARMv7 Thumb-2 numerical leaves.
 *
 * This deliberately bounded bring-up uses DMD's real parser and all semantic
 * passes. Unsupported constructs are errors, never silently omitted code.
 * Existing AArch64 code generation stays in the ordinary Mars backend.
 *
 * License: Boost License 1.0
 */
module dmd.glue.thumb;

import dmd.astenums : TY, STC, LINK, VarArg, FileType;
import dmd.arraytypes : Dsymbols;
import dmd.typesem : toBasetype;
import dmd.backend.thumb;
import dmd.declaration;
import dmd.dmodule;
import dmd.dsymbol;
import dmd.dsymbolsem : include;
import dmd.errors : error;
import dmd.expression;
import dmd.func;
import dmd.globals : global;
import dmd.init;
import dmd.location;
import dmd.mtype;
import dmd.root.string : toDString;
import dmd.statement;
import dmd.tokens : EXP;
import std.file : write, exists, remove, mkdirRecurse, rename;
import std.path : dirName;


private class UnsupportedThumb : Exception
{
    Loc location;
    this(Loc location, string message)
    {
        super(message);
        this.location = location;
    }
}

private void reject(Loc loc, string message)
{
    throw new UnsupportedThumb(loc, message);
}

private bool word_type(Type t)
{
    if (!t) return false;
    const ty = t.toBasetype().ty;
    return ty == TY.Tint32 || ty == TY.Tuns32 || ty == TY.Tfloat32 ||
           ty == TY.Tbool || ty == TY.Tpointer;
}

private bool floating(Type t) { return t && t.toBasetype().ty == TY.Tfloat32; }

private string c_symbol_name(FuncDeclaration function_, Loc loc)
{
    string name = function_.mangleOverride.length ? function_.mangleOverride.idup :
                  function_.ident.toString().idup;
    foreach (i, ch; name)
        if (!((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_' ||
              (i > 0 && ch >= '0' && ch <= '9')))
            reject(loc, "Thumb ELF symbol must be a nonempty ASCII C identifier");
    if (!name.length) reject(loc, "empty Thumb symbol");
    return name;
}

private struct LeafEmitter
{
    ThumbCode code;
    uint[VarDeclaration] homes;
    uint slots;
    size_t[] returns;
    ThumbCall[] calls;
    struct LoopEdges { size_t[] breaks; size_t[] continues; }
    LoopEdges[] loops;
    Loc location;
    uint depth;

    uint temporary()
    {
        if (slots >= 126) reject(location, "leaf frame exceeds 504 bytes");
        return slots++;
    }

    uint home(VarDeclaration variable)
    {
        auto found = variable in homes;
        if (!found) reject(variable.loc, "global, captured, or uninitialised variable is outside the leaf subset");
        return *found;
    }

    void require_word(Type t, Loc loc)
    {
        if (!word_type(t)) reject(loc, "only float, int, uint, bool and pointers are supported in Thumb leaves");
    }

    void condition(Expression expression_)
    {
        expression(expression_);
        if (floating(expression_.type))
        {
            // IEEE truth: both signed zeros are false, NaN is true.
            code.half(0x0040); // LSLS r0, r0, #1; remove sign bit
        }
        code.half(0x2800); // CMP r0, #0
    }

    void address(Expression expression_)
    {
        if (auto index = expression_.isIndexExp())
        {
            if (index.e1.type.toBasetype().ty != TY.Tpointer ||
                !word_type(index.type) || index.type.toBasetype().ty == TY.Tbool)
                reject(index.loc, "only caller-owned four-byte pointer elements are supported");
            expression(index.e1);
            const saved = temporary();
            code.store(saved);
            expression(index.e2);
            code.half(0x4601); // MOV r1, r0
            code.half(0x0089); // LSLS r1, r1, #2
            code.load(saved);
            code.half(0x1840); // ADDS r0, r0, r1
            return;
        }
        if (expression_.op == EXP.star)
        {
            if (expression_.type.toBasetype().ty == TY.Tbool)
                reject(expression_.loc, "byte-sized memory accesses are not implemented");
            expression(expression_.isUnaExp().e1);
            return;
        }
        reject(expression_.loc, "unsupported address expression in Thumb leaf");
    }

    void assign(Expression destination)
    {
        if (auto variable = destination.isVarExp())
        {
            auto declaration = variable.var.isVarDeclaration();
            if (!declaration) reject(destination.loc, "assignment target is not a local variable");
            code.store(home(declaration));
            return;
        }
        const saved = temporary();
        code.store(saved);
        address(destination);
        code.load(saved, 1);
        code.half(0x6001); // STR r1, [r0]
        code.half(0x4608); // MOV r0, r1: assignment evaluates to stored value
    }

    void declare(VarDeclaration variable)
    {
        require_word(variable.type, variable.loc);
        if (variable.storage_class & (STC.static_ | STC.ref_ | STC.out_ | STC.lazy_))
            reject(variable.loc, "static and by-reference locals are outside the leaf subset");
        homes[variable] = temporary();
        auto initializer = variable._init ? variable._init.isExpInitializer() : null;
        if (!initializer) reject(variable.loc, "local requires an expression initializer");
        expression(initializer.exp);
        code.store(home(variable));
    }

    void expression(Expression e)
    {
        if (!e) return;
        if (++depth > 128) reject(e.loc, "Thumb expression nesting exceeds 128");
        scope(exit) --depth;
        if (e.type && e.type.toBasetype().ty != TY.Tvoid && e.op != EXP.declaration)
            require_word(e.type, e.loc);
        if (auto integer = e.isIntegerExp()) { code.constant(cast(uint)integer.value); return; }
        if (auto real_constant = e.isRealExp())
        {
            if (!floating(e.type)) reject(e.loc, "only binary32 floating constants are supported");
            union Payload { float value; uint bits; }
            Payload payload;
            payload.value = cast(float)real_constant.value;
            code.constant(payload.bits);
            return;
        }
        if (e.op == EXP.null_) { code.constant(0); return; }
        if (auto call = e.isCallExp())
        {
            auto callee = call.e1 ? call.e1.isVarExp() : null;
            auto function_ = callee ? callee.var.isFuncDeclaration() : null;
            if (!function_)
                reject(e.loc, "only direct extern(C) function calls are supported");

            auto signature = function_.type.toTypeFunction();
            if (function_.resolvedLinkage() != LINK.c || function_.isNested() || function_.isMember() ||
                signature.isRef || signature.parameterList.varargs != VarArg.none)
                reject(e.loc, "direct calls require top-level non-variadic extern(C) functions");
            if (function_.parameters && function_.parameters.length > 4)
                reject(e.loc, "Thumb softfp direct call accepts at most four one-word arguments");

            if (signature.next.toBasetype().ty != TY.Tvoid)
                require_word(signature.next, e.loc);

            if (function_.parameters) foreach (parameter; *function_.parameters)
            {
                require_word(parameter.type, parameter.loc);
                if (parameter.storage_class & (STC.ref_ | STC.out_ | STC.lazy_))
                    reject(parameter.loc, "direct-call ref/out/lazy parameters are outside the leaf subset");
            }

            uint[] saved;
            if (call.arguments) foreach (argument; *call.arguments)
            {
                require_word(argument.type, argument.loc);
                expression(argument);
                saved ~= temporary();
                code.store(saved[$ - 1]);
            }
            if (saved.length > 4)
                reject(e.loc, "Thumb softfp direct call accepts at most four one-word arguments");
            foreach (i, slot; saved)
                code.load(slot, cast(uint)i);

            calls ~= ThumbCall(code.call(), c_symbol_name(function_, e.loc));
            return;
        }
        if (auto variable = e.isVarExp())
        {
            auto declaration = variable.var.isVarDeclaration();
            if (!declaration) reject(e.loc, "function values are outside the leaf subset");
            code.load(home(declaration)); return;
        }
        if (auto declaration = e.isDeclarationExp())
        {
            auto variable = declaration.declaration.isVarDeclaration();
            if (!variable) reject(e.loc, "only scalar local declarations are supported");
            declare(variable); return;
        }
        if (auto cast_ = e.isCastExp())
        {
            if (cast_.type.toBasetype().ty == TY.Tbool)
            { condition(cast_.e1); code.boolean_result(1); return; }
            if (floating(cast_.type) != floating(cast_.e1.type))
                reject(e.loc, "integer/float conversions are not implemented in this Thumb slice");
            require_word(cast_.e1.type, e.loc);
            expression(cast_.e1);
            if (e.type.toBasetype().ty == TY.Tbool)
            { code.half(0x2800); code.boolean_result(1); }
            return;
        }
        if (e.op == EXP.index || e.op == EXP.star)
        { address(e); code.half(0x6800); return; } // LDR r0, [r0]
        if (e.op == EXP.negate || e.op == EXP.uadd || e.op == EXP.not)
        {
            auto operand = e.isUnaExp().e1;
            if (e.op == EXP.not) { condition(operand); code.boolean_result(0); return; }
            expression(operand);
            if (e.op == EXP.uadd) return;
            if (floating(operand.type))
            {
                code.wide(0xEE00, 0x0A10); // VMOV s0, r0
                code.wide(0xEEB1, 0x0A40); // VNEG.F32 s0, s0
                code.wide(0xEE10, 0x0A10); // VMOV r0, s0
            }
            else code.half(0x4240); // RSBS r0, r0, #0
            return;
        }
        if (auto choice = e.isCondExp())
        {
            condition(choice.econd);
            auto otherwise = code.conditional(0);
            expression(choice.e1);
            auto done = code.branch();
            code.resolve(otherwise, code.bytes.length);
            expression(choice.e2);
            code.resolve(done, code.bytes.length);
            return;
        }
        if (e.op == EXP.halt) { code.half(0xDE00); return; }
        auto binary = e.isBinExp();
        if (!binary) reject(e.loc, "unsupported expression in Thumb leaf (calls, allocation and runtime features are not implemented)");
        if (e.op == EXP.comma) { expression(binary.e1); expression(binary.e2); return; }
        if (e.op == EXP.assign || e.op == EXP.construct || e.op == EXP.blit)
        { expression(binary.e2); assign(binary.e1); return; }
        if (e.op == EXP.andAnd || e.op == EXP.orOr)
        {
            condition(binary.e1);
            auto short_circuit = code.conditional(e.op == EXP.andAnd ? 0 : 1);
            condition(binary.e2);
            code.boolean_result(1);
            auto done = code.branch();
            code.resolve(short_circuit, code.bytes.length);
            code.half(e.op == EXP.andAnd ? 0x2000 : 0x2001);
            code.resolve(done, code.bytes.length);
            return;
        }
        expression(binary.e1);
        const saved = temporary(); code.store(saved);
        expression(binary.e2);
        code.half(0x4601); code.load(saved); // left r0, right r1
        const fp = floating(binary.e1.type);
        const unsigned_ = binary.e1.type.toBasetype().ty == TY.Tuns32 ||
                          binary.e1.type.toBasetype().ty == TY.Tpointer;
        if (fp)
        { code.wide(0xEE00, 0x0A10); code.wide(0xEE00, 0x1A90); }
        switch (e.op)
        {
            case EXP.add: if (fp) code.wide(0xEE30, 0x0A20); else code.half(0x1840); break;
            case EXP.min: if (fp) code.wide(0xEE30, 0x0A60); else code.half(0x1A40); break;
            case EXP.mul: if (fp) code.wide(0xEE20, 0x0A20); else code.half(0x4348); break;
            case EXP.div:
                if (!fp) reject(e.loc, "integer division is not implemented in this Thumb slice");
                code.wide(0xEE80, 0x0A20); break;
            case EXP.and: code.half(0x4008); break;
            case EXP.or:  code.half(0x4308); break;
            case EXP.xor: code.half(0x4048); break;
            case EXP.equal: case EXP.notEqual:
            case EXP.lessThan: case EXP.lessOrEqual:
            case EXP.greaterThan: case EXP.greaterOrEqual:
            {
                if (fp)
                { code.wide(0xEEB4, 0x0A60); code.wide(0xEEF1, 0xFA10); }
                else code.half(0x4288); // CMP r0, r1
                uint cc;
                switch (e.op)
                {
                    case EXP.equal:          cc = 0; break;
                    case EXP.notEqual:       cc = 1; break;
                    case EXP.lessThan:       cc = fp ? 4 : unsigned_ ? 3 : 11; break;
                    case EXP.lessOrEqual:    cc = fp || unsigned_ ? 9 : 13; break;
                    case EXP.greaterThan:    cc = fp ? 12 : unsigned_ ? 8 : 12; break;
                    case EXP.greaterOrEqual: cc = fp ? 10 : unsigned_ ? 2 : 10; break;
                    default: assert(0);
                }
                code.boolean_result(cc); return;
            }
            default: reject(e.loc, "unsupported binary operation in Thumb leaf");
        }
        if (fp) code.wide(0xEE10, 0x0A10);
    }

    void statement(Statement s)
    {
        if (!s) return;
        if (auto block = s.isCompoundStatement())
        { if (block.statements) foreach (child; *block.statements) statement(child); return; }
        if (auto block = s.isCompoundDeclarationStatement())
        { if (block.statements) foreach (child; *block.statements) statement(child); return; }
        if (auto scope_ = s.isScopeStatement()) { statement(scope_.statement); return; }
        if (auto e = s.isExpStatement()) { expression(e.exp); return; }
        if (auto ret = s.isReturnStatement())
        {
            expression(ret.exp);
            returns ~= code.bytes.length;
            code.half(0xB000); code.half(0xBD10); // ADD sp, #frame; POP {r4, pc}
            return;
        }
        if (auto branch = s.isIfStatement())
        {
            condition(branch.condition);
            auto otherwise = code.conditional(0);
            statement(branch.ifbody);
            auto done = code.branch();
            code.resolve(otherwise, code.bytes.length);
            statement(branch.elsebody);
            code.resolve(done, code.bytes.length);
            return;
        }
        if (auto loop = s.isForStatement())
        { emit_loop(loop._init, loop.condition, loop.increment, loop._body); return; }
        if (auto loop = s.isWhileStatement())
        { emit_loop(null, loop.condition, null, loop._body); return; }
        if (auto break_ = s.isBreakStatement())
        {
            if (!loops.length || break_.ident) reject(s.loc, "labelled or non-loop break is unsupported");
            loops[$-1].breaks ~= code.branch(); return;
        }
        if (auto continue_ = s.isContinueStatement())
        {
            if (!loops.length || continue_.ident) reject(s.loc, "labelled or non-loop continue is unsupported");
            loops[$-1].continues ~= code.branch(); return;
        }
        if (s.isImportStatement()) return;
        reject(s.loc, "unsupported statement in Thumb leaf");
    }

    void emit_loop(Statement init, Expression test, Expression increment, Statement body)
    {
        statement(init);
        const start = code.bytes.length;
        loops ~= LoopEdges.init;
        if (test) { condition(test); loops[$-1].breaks ~= code.conditional(0); }
        statement(body);
        foreach (edge; loops[$-1].continues) code.resolve(edge, code.bytes.length);
        expression(increment);
        const back = code.branch(); code.resolve(back, start);
        foreach (edge; loops[$-1].breaks) code.resolve(edge, code.bytes.length);
        loops.length--;
    }

    ThumbFunction emit(FuncDeclaration function_)
    {
        location = function_.loc;
        if (function_.resolvedLinkage() != LINK.c || function_.isNested() || function_.isMember())
            reject(location, "Thumb bring-up accepts top-level extern(C) leaves only");
        auto signature = function_.type.toTypeFunction();
        if (signature.parameterList.varargs != VarArg.none || signature.isRef)
            reject(location, "variadic or ref-return functions are outside the leaf subset");
        auto result = signature.next;
        if (result.toBasetype().ty != TY.Tvoid) require_word(result, location);
        if (function_.parameters && function_.parameters.length > 4)
            reject(location, "Thumb softfp leaf accepts at most four one-word arguments");
        string name = c_symbol_name(function_, location);
        code.half(0xB510); // PUSH {r4, lr}; keeps the public stack 8-byte aligned
        code.half(0xB080); // frame size patched after allocating all homes
        if (function_.parameters) foreach (i, parameter; *function_.parameters)
        {
            require_word(parameter.type, parameter.loc);
            if (parameter.storage_class & (STC.ref_ | STC.out_ | STC.lazy_))
                reject(parameter.loc, "ref/out/lazy parameters are outside the leaf subset");
            homes[parameter] = temporary();
            code.store(homes[parameter], cast(uint)i);
        }
        statement(function_.fbody);
        if (result.toBasetype().ty == TY.Tvoid)
        { returns ~= code.bytes.length; code.half(0xB000); code.half(0xBD10); }
        else code.half(0xDE00); // unreachable fallthrough traps rather than returning garbage
        const frame = (slots * 4 + 7) & ~7U;
        code.patch_half(2, 0xB080 | frame / 4);
        foreach (at; returns) code.patch_half(at, 0xB000 | frame / 4);
        return ThumbFunction(name, code.bytes, calls);
    }
}

void generate_thumb_objects(Module[] modules)
{
    // Build every object in memory before touching destinations. On a rejected
    // module, remove outputs rather than leaving a stale successful object.
    ubyte[][] objects;
    string[] paths;
    try
    {
        foreach (module_; modules)
        {
            if (module_.filetype == FileType.dhdr) continue;
            ThumbFunction[] functions;
            bool[string] names;
            void members(Dsymbols* symbols)
            {
                if (!symbols) return;
                foreach (symbol; *symbols)
                {
                    if (auto attr = symbol.isAttribDeclaration())
                    { members(include(attr, null)); continue; }
                    if (auto function_ = symbol.isFuncDeclaration())
                    {
                        if (!function_.fbody) continue;
                        LeafEmitter emitter;
                        auto leaf = emitter.emit(function_);
                        if (leaf.name in names) reject(function_.loc, "duplicate Thumb external symbol");
                        names[leaf.name] = true;
                        functions ~= leaf;
                        continue;
                    }
                    if (symbol.isImport() || symbol.isAliasDeclaration() ||
                        symbol.isEnumDeclaration() || symbol.isStaticAssert()) continue;
                    if (auto variable = symbol.isVarDeclaration())
                        if (variable.storage_class & STC.manifest) continue;
                    reject(symbol.loc, "declaration needs runtime or data emission outside the Thumb leaf subset");
                }
            }
            members(module_.members);
            objects ~= thumb_object(functions);
            paths ~= module_.objfile.toString().idup;
        }
        foreach (i, path; paths)
        {
            auto parent = dirName(path);
            if (parent.length && !exists(parent)) mkdirRecurse(parent);
            const temporary_path = path ~ ".thumb-tmp";
            write(temporary_path, objects[i]);
            rename(temporary_path, path);
        }
    }
    catch (UnsupportedThumb failure)
    {
        foreach (module_; modules) if (module_.filetype != FileType.dhdr) module_.deleteObjFile();
        error(failure.location, "Thumb-2 backend: %.*s", cast(int)failure.msg.length, failure.msg.ptr);
    }
    catch (Exception failure)
    {
        foreach (module_; modules) if (module_.filetype != FileType.dhdr) module_.deleteObjFile();
        error(Loc.initial, "Thumb-2 emission failed: %.*s", cast(int)failure.msg.length, failure.msg.ptr);
    }
}
