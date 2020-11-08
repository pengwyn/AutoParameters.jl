module AutoParameters

export @AutoParm,
    WidestParamType

using MacroTools: @capture, @q, block, postwalk, isexpr, striplines, isshortdef

# Convenient iteration flatten
# My version of flatten1, which doesn't remove blocks at the top level (this ruins structs)
function my_flatten1(ex)
  isexpr(ex, :block) || return ex
  #ex′ = :(;)
  ex′ = Expr(:block)
  for x in ex.args
    isexpr(x, :block) ? append!(ex′.args, x.args) : push!(ex′.args, x)
  end
  return ex′
end
iterflatten(ex) = postwalk(my_flatten1, block(ex)).args


##############################
# * AutoParm
#----------------------------

macro AutoParm(expr)
    expr = macroexpand(__module__, expr)
    AutoParmFunc(expr)
end
function AutoParmFunc(expr)
    count = 0
    args = map(iterflatten(expr)) do expr
        if @capture (expr) (mutable struct combname_ raw_fields__ end)
            ismutable = true
        elseif @capture (expr) (struct combname_ raw_fields__ end)
            ismutable = false
        else
            # error("Does not match the form expected")
            # return esc(expr)
            return expr
        end

        count += 1

        @assert @capture (combname) ( 
            (name_{Tstruct__} <: SUPER_) |
            (name_ <: SUPER_) |
            (name_{Tstruct__}) |
            (name_))

        name = esc(name)
        SUPER = SUPER === nothing ? Any : esc(SUPER)
        Tstruct = Tstruct === nothing ? [] : esc.(Tstruct)
        
        all_params = []
        all_params_supers = []

        for param in Tstruct
            @capture (param) (
                (name_) | (name_ <: super_)
            )
            push!(all_params, esc(name))
            push!(all_params_supers, esc(super))
        end

        out_fields = []
        out_types = []
        out_defaults = []
        out_supertypes = []

        out_functions = []

        for (ind,field) in enumerate(raw_fields)
            # Note: isdef no longer works it seems
            if isshortdef(field) || (field isa Expr && field.head == :function)
                push!(out_functions, field)
                continue
            end
            
            if !@capture (field) (fieldname_::T_ <: Tsuper_ = default_) |
                (fieldname_::T_ = default_) |
                (fieldname_ = default_) |
                (fieldname_::T_ <: Tsuper_) |
                (fieldname_::T_) |
                (fieldname_)
                @error "Field doesn't make sense!" field
            end

            if T == nothing
                T = Any
                Tsuper = Any
            elseif T == :AUTO
                T = Symbol(uppercase.("T_$(fieldname)"))
                if Tsuper == nothing
                    Tsuper = Any
                end
                push!(all_params, esc(T))
                push!(all_params_supers, esc(Tsuper))
            else
                Tsuper = T
            end

            push!(out_fields, esc(fieldname))
            push!(out_types, esc(T))
            push!(out_supertypes, esc(Tsuper))
            push!(out_defaults, esc(default))
        end

        unesc(x) = x.args[]
        join_expr(a,sym,b) = Expr(sym, a, b)

        make_conv(args...) = :(convert($(args...)))
        function make_paramed(T, args...)
            if isempty(args)
                :($T)
            else
                :($T{$(args...)})
            end
        end

        expr = :(
            mutable struct $(name){$(join_expr.(all_params, :(<:), all_params_supers)...)} <: $(SUPER)
            $(join_expr.(unesc.(out_fields), :(::), out_types)...)

            function $(make_paramed(name, all_params...))($(out_fields...)) where {$(join_expr.(all_params, :(<:), all_params_supers)...)}
                new{$(all_params...)}($(out_fields...))
            end

            function $(name)($(join_expr.(out_fields, :(::), out_types)...)) where {$(join_expr.(all_params, :(<:), all_params_supers)...)}
                new{$(all_params...)}($(out_fields...))
            end

            function $(name)($(out_fields...))
                $(name)($(make_conv.(out_supertypes, out_fields)...))
            end

            $out_functions
            end)

        expr.args[1] = ismutable
        expr = striplines(expr)

        function field_with_default(field,default)
            if default === nothing
                :($field)
            else
                Expr(:kw, field, default)
            end
        end
        
        defaults_kwd_expr = @q begin
            (::$Type{T})(; $(field_with_default.(out_fields, out_defaults)...)) where {T <: $name} = T($(out_fields...))
        end

        
        defaults_dict_inner = [:($(QuoteNode(unesc(name))) => ()->$(unesc(default))) for (name,default) in zip(out_fields,out_defaults) if default != nothing]
        defaults_dict = :(Dict{Symbol,Any}($(defaults_dict_inner...)))

        @q begin
            Base.@__doc__ $expr

            $defaults_kwd_expr
            
            const $(esc(Symbol("AUTOPARM_",unesc(name),"_defaults"))) = $(esc(defaults_dict))
        end
    end
    if count != 1
        error("Does not match the form expected - $count")
    end

    expr = Expr(:block, args...)

    return expr
end


function WidestParamType(thetype)
    while !isconcretetype(thetype)
        thetype = thetype{thetype.var.ub}
    end
    thetype
end


end # module
