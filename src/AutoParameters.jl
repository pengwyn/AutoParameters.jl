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

        unesc(x) = x.args[]
        join_expr(a,sym,b) = Expr(sym, a, b)

        make_conv(args...) = :(convert($(args...)))


        count += 1

        @assert @capture (combname) ( 
            (name_{Tstruct__} <: SUPER_) |
            (name_ <: SUPER_) |
            (name_{Tstruct__}) |
            (name_))

        name = esc(name)
        SUPER = SUPER === nothing ? Any : esc(SUPER)
        Tstruct = Tstruct === nothing ? [] : Tstruct
        
        all_params = []
        all_params_supers = []


        for param in Tstruct
            @capture (param) (
                (param_name_ <: super_) | (param_name_)
            )
            push!(all_params, esc(param_name))
            super = super === nothing ? Any : super
            push!(all_params_supers, esc(super))
        end

        explicit_params = copy(all_params)
        explicit_params_supers = copy(all_params_supers)

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
                ind = findfirst(==(esc(T)), all_params)
                if ind === nothing
                    Tsuper = T
                else
                    Tsuper = unesc(all_params_supers[ind])
                end
            end

            default = default === nothing ? nothing : esc(default)

            push!(out_fields, esc(fieldname))
            push!(out_types, esc(T))
            push!(out_supertypes, esc(Tsuper))
            push!(out_defaults, default)
        end

        function field_with_default(field,default)
            if default === nothing
                :($field)
            else
                Expr(:kw, field, default)
            end
        end

        expr = :(
            mutable struct $(name){$(join_expr.(all_params, :(<:), all_params_supers)...)} <: $(SUPER)
                $(join_expr.(unesc.(out_fields), :(::), out_types)...)

                # Convert constructor - only if there's a single type specified and all explicit params must also be given
                $(all(unesc.(out_supertypes) .== Any) ? nothing :
                    :(function $(name){$(explicit_params...)}($(out_fields...)) where {$(join_expr.(explicit_params, :(<:), explicit_params_supers)...)}
                            $(name)($(make_conv.(out_supertypes, out_fields)...))
                      end)
                  )

                # Explicit param constructor - only if there are params
                $(isempty(all_params) ? nothing :
                    :(function $(name){$(all_params...)}($(join_expr.(out_fields, :(::), out_types)...)) where {$(join_expr.(all_params, :(<:), all_params_supers)...)}
                        new{$(all_params...)}($(out_fields...))
                      end)
                  )

                # Constructor with params but correct types - this will not convert by default.
                function $(name)($(join_expr.(out_fields, :(::), out_types)...)) where {$(join_expr.(all_params, :(<:), all_params_supers)...)}
                    new{$(all_params...)}($(out_fields...))
                end

                # Keyword constructor
                function (::$Type{T})(; $(field_with_default.(out_fields, out_defaults)...)) where {T <: $name}
                    T($(out_fields...))
                end

                # Convenience keyword constructor that shouldn't be overwritten
                function (::$Type{T})(::Val{:constructor} ; $(field_with_default.(out_fields, out_defaults)...)) where {T <: $name}
                    T($(out_fields...))
                end

                $out_functions
            end)

        expr.args[1] = ismutable
        expr = striplines(expr)

        # Remove any bad where statements
        expr = postwalk(expr) do ex
            if ex isa Expr && ex.head ∈ [:where,:curly] && length(ex.args) == 1
                return ex.args[]
            end
            ex
        end

        
        defaults_dict_inner = [:($(QuoteNode(unesc(name))) => ()->$(unesc(default))) for (name,default) in zip(out_fields,out_defaults) if default != nothing]
        defaults_dict = :(Dict{Symbol,Any}($(defaults_dict_inner...)))

        @q begin
            Base.@__doc__ $expr

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
