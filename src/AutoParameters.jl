module AutoParameters

export @AutoParm,
    WidestParamType

using MacroTools: @capture, @q, block, postwalk, isexpr, striplines, isdef

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

"""
TryConvert

This is used to convert (if necessary) the arguments to a conforming type,
allowing for more flexible automatic type choosing.
"""
TryConvert(val::T, ::Type{T_SUPER}) where {T_SUPER, T <: T_SUPER} = val
TryConvert(val::T, ::Type{T_SUPER}) where {T_SUPER, T} = convert(T_SUPER, val)

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

        if Tstruct == nothing
            Tstruct = []
        end

        extra_params = []
        extra_params_subtype = []
        extra_params_supertype = []
        extra_constructor = []

        out_fields = []
        out_types = []
        out_defaults = []
        out_supertypes = []

        out_functions = []

        fields = []

        for (ind,field) in enumerate(raw_fields)
            # # This is for something dodgy I wanted to do once
            # if @capture (field) ()
            #     continue
            # end
            if isdef(field)
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
                if Tsuper != nothing
                    typeinfo = :($T <: $Tsuper)
                else
                    typeinfo = T
                    Tsuper = Any
                end
                push!(extra_params, T)
                push!(extra_params_subtype, typeinfo)
                # push!(extra_constructor, :(typeof(args[$ind])))
            else
                Tsuper = T
            end

            push!(out_fields, fieldname)
            push!(out_types, T)
            push!(out_supertypes, Tsuper)
            push!(out_defaults, default)

            push!(fields, :($fieldname::$T))
        end

        full_Tstruct = (Tstruct..., extra_params_subtype...)
        Tstruct_names = map(Tstruct) do item
            item isa Symbol && return item
            @assert item.head == :<:
            return item.args[1]
        end

        e_full_Tstruct = esc.(full_Tstruct)
        e_Tstruct = esc.(Tstruct)
        e_Tstruct_names = esc.(Tstruct_names)
        e_name = esc(name)
        e_create_name = esc(Symbol(:_Create,name))
        e_out_fields = esc.(out_fields)
        e_out_defaults = esc.(out_defaults)
        e_out_supertypes = esc.(out_supertypes)

        out_fields_typed = [:($field::$T) for (field,T) in zip(out_fields, out_types)]
        out_fields_typed_defaults = [default == nothing ? var : Expr(:kw, var, default)
                                     for (var,default) in zip(out_fields_typed, out_defaults)]

        out_fields_defaults = [default == nothing ? var : Expr(:kw, var, default)
                                     for (var,default) in zip(out_fields, out_defaults)]

        e_out_fields_typed = esc.(out_fields_typed)
        e_out_fields_typed_defaults = esc.(out_fields_typed_defaults)
        e_out_fields_defaults = esc.(out_fields_defaults)

        # out_kwds = [(default == nothing ? name : Expr(:kw, name, esc(default))) for (name,default) in zip(e_out_fields,out_defaults)]
        out_kwds = e_out_fields_typed_defaults

        last_mandatory = findlast(x->x==nothing, out_defaults)
        if last_mandatory == nothing
            last_mandatory = 1
        end

        if last_mandatory < length(out_kwds)
            out_args = copy(out_kwds) |> Vector{Any}
            out_args[1:last_mandatory] = e_out_fields_typed[1:last_mandatory]

            defaults_arg_expr = @q begin
                $e_name($(out_args[1:end-1]...)) where {$(e_full_Tstruct...)} = $e_name($(e_out_fields[1:end-1]...), $(e_out_defaults[end]))
            end
        else
            # defaults_arg_expr = :(begin end)
            defaults_arg_expr = nothing
        end

        # This is a bit of crass relabelling just so we can always have a keywords method which is not overwritten
        # I.e. we can redefine CLASS(a=1,b=2) to call _CreateCLASS(; real_field_a=a, real_field_b=b+1, ...)
        defaults_kwd_expr = @q begin
            # $e_create_name(; $(out_kwds...)) where {$(e_full_Tstruct...)} = $e_name($(e_out_fields...))
            # $e_name(; kwds...) where {$(e_full_Tstruct...)} = $e_create_name(; kwds...)
            $e_create_name(thetype=$e_name ; $(e_out_fields_defaults...)) = thetype($(e_out_fields...))
            # $e_create_name(; kwds...) = $e_create_name($e_name ; kwds...)
            # $e_name(; kwds...) = $e_create_name(; kwds...)
            (::$Type{T})(; kwds...) where {T<:$e_name} = $e_create_name(T; kwds...)
            # TODO: Perhaps introduce the cascade of partially applied types, to
            # then put in the most narrow type until a concrete T is reached.
        end
        
        defaults_dict_inner = [:($(QuoteNode(name)) => ()->$default) for (name,default) in zip(out_fields,out_defaults) if default != nothing]
        defaults_dict = :(Dict{Symbol,Any}($(defaults_dict_inner...)))


        # This is to allow for convert(T, x) by default. This is to try and
        # match with the default hidden constructor in Julia, although that
        # constructor is only defined for non-parameteric types.

        # But only do this if there is at least one type which is not Any. Otherwise, this will hit an endless loop.
        if all(==(Any), out_supertypes)
            fallback_convert_expr = nothing
        elseif isempty(full_Tstruct)
            fallback_convert_expr = nothing
        else
            convert_expr = map(e_out_fields,e_out_supertypes) do name,super
                :(convert($super, $name))
            end
            fallback_convert_expr = @q begin
                $e_name($(e_out_fields...)) = $e_name($(convert_expr...))
            end
        end

        # And one variety for all explicit parameters, filling in the remainder
        # TODO: Broken! Need to make this consider each extra param separately,
        # do the attempted conversion, then add it into the specialisation of
        # the type.
        # if !isempty(Tstruct) && !isempty(extra_params)
        #     T = :($e_name{$(e_Tstruct_names...)})
        #     convert_expr = map(out_fields,out_supertypes) do name,super
        #         :(convert($(esc(super)), $(esc(name))))
        #     end

        #     explicit_convert_expr = @q begin
        #         # (::$Type{T})($(e_out_fields_defaults...)) where {$(e_Tstruct...), T <: $T} = T($(convert_expr...))
        #         $T($(e_out_fields_defaults...)) where {$(e_Tstruct...)} = $T($(convert_expr...))
        #     end
        # else
            explicit_convert_expr = nothing
        # end


        expr = :(
            mutable struct $e_name{$(e_full_Tstruct...)}
            $(esc.(fields)...)
            $(esc.(out_functions)...)
            end)
        expr.args[1] = ismutable
        if SUPER != nothing
            expr.args[2] = :($(expr.args[2]) <: $(esc(SUPER)))
        end
        expr = striplines(expr)

        @q begin
            Base.@__doc__ $expr

            $defaults_arg_expr
            $fallback_convert_expr
            $explicit_convert_expr
            $defaults_kwd_expr
            
            # $type_constructor_expr

            const $(esc(Symbol("AUTOPARM_",name,"_defaults"))) = $(esc(defaults_dict))
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
