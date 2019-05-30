using Core: SSAValue

# Utilities for calling into the internals of the flisp frontend as required to
# support the porting effort.

function fl_expand_forms(ex)
    ccall(:jl_call_scm_on_ast, Any, (Cstring, Any, Any), "julia-expand0", ex, Main)
end

function _canonicalize_form!(ex, nextid, valmap)
    if ex isa SSAValue
        # Rename SSAValues into renumbered symbols
        return get!(valmap, ex) do
            newid = nextid[]
            nextid[] = newid+1
            Symbol("ssa$newid")
        end
    end
    while ex isa Expr && ex.head == :block
        # Remove trivial blocks
        filter!(e->!(e isa LineNumberNode), ex.args)
        if length(ex.args) != 1
            break
        end
        ex = ex.args[1]
    end
    if ex isa Expr
        filter!(e->!(e isa LineNumberNode), ex.args)
        map!(ex.args, ex.args) do e
            _canonicalize_form!(e, nextid, valmap)
        end
    end
    return ex
end

# Replace SSAValue(id) with consecutively numbered symbols "ssa$newid" which
# can be entered by hand in the test cases.
function canonicalize_form(ex)
    valmap = Dict{SSAValue,Symbol}()
    nextid = Ref(0)
    _canonicalize_form!(deepcopy(ex), nextid, valmap)
end

macro test_expand_forms(in, ref)
    quote
        @test canonicalize_form(fl_expand_forms($in)) == canonicalize_form($ref)
    end
end

@testset "Expand comparison chains" begin

    @test_expand_forms quote
            a < b+c < d
        end quote
            if (ssa0 = b+c; a < ssa0)
                ssa0 < d
            else
                false
            end
        end

    Base_materialize = GlobalRef(Base, :materialize)
    Base_broadcasted = GlobalRef(Base, :broadcasted)

    @test_expand_forms quote
            a .< b < c
        end quote
            $Base_materialize($Base_broadcasted(&, $Base_broadcasted(<, a, b), b < c))
        end
end
