# AutoParameters.jl
A combination of automatic parameterised types and default values for structs.
The main use case for me is to allow for dispatching on a struct of parameters,
rather than separate function arguments.

To use, put `@AutoParm` in front of a struct. This will create a default
keyword-only constructor and a pure value constructor. Each field can be
designated as an `AUTO` type, which will add it to the struct parameters with a
generated name. These can also be indicated to be a subtype. Syntax:
 
```julia
@AutoParm struct MyType
    field::AUTO <: SuperType = default values
end
```

For example:

```julia
julia> @AutoParm struct TEST
           a::AUTO <: AbstractArray{Float64} = [1,2,3]
           b::AUTO <: Real
           c::Int = 3
       end

julia> TEST(b=1)
TEST{Array{Float64,1},Int64}([1.0, 2.0, 3.0], 1, 3)

julia> TEST([1.0], 0)
TEST{Array{Float64,1},Int64}([1.0], 0, 3)

```

As I often create structs with some kind of complex defaults, but I don't want
to be locked into the parameters of the type when the defaults are being set, a
`WidestParamType` is available. It is meant to be used in this style:

```julia
# Package code:
@AutoParm mutable struct PARAMS
    grid::AUTO <: AbstractVector
    scale_factor::Float64 = 5.0
    some_function::AUTO <: Union{Nothing,Function} = nothing
end

function PARAMS(; overall_style=:something_complex)
    complex_calculation = [1,2,3]
    WidestParamType(PARAMS)(grid=complex_calculation)
end
Finalise(x::PARAMS) = PARAMS(fieldvalues(x)...)
```

and then the user code can do something like:

```julia
# Initial default struct
obj = PARAMS(overall_style=:specific_thing)

# Changing settings
obj.grid = obj.scale_factor * LinRange(0,1,101)
MyUpdate(x) = println("Updating x!")
obj.some_function = MyUpdate

# Finalise the object to be the narrowest types
obj2 = Finalise(obj)

typeof(obj) == PARAMS{AbstractVector,Union{Nothing,Function}}
typeof(obj2) == PARAMS{LinRange{Float64}, typeof(MyUpdate)}
```

This means that any function using a `PARAMS` object will dispatch knowing that
it has an interesting `some_function` and a `LinRange` for the grid, however I
wasn't locked into this when creating the initial object. I was also able to use
a default value from the object (`scale_factor`) in updating the object.
 
## Other generated items

A backup constructor `_Create<name>` is also generated to allow for overwriting
of the default keyword-only constructor. This allows for:

```julia
MyType(; special) = _CreateMyType(; fieldone=special, fieldtwo="nothing")
```

The default values can also be accessed through `AUTOPARM_<name>_defaults`:

```julia
AUTOPARM_TEST_defaults[:a]() == [1,2,3]
```

Note that these defaults are themselves functions. This is to mimic keyword
functions, avoiding contamination of default values between function calls.

## Generated code

For the first example, the generated code looks like:

```julia
julia> using MacroTools

julia> @expand @AutoParm struct TEST
              a::AUTO <: AbstractArray{Float64} = [1,2,3]
              b::AUTO <: Real
              c::Int = 3
              end
quote
    begin
        struct TEST{T_A <: AbstractArray{Float64}, T_B <: Real}
            a::T_A
            b::T_B
            c::Int
        end
        begin
            (TEST(a::T_A, b::T_B) where {T_A <: AbstractArray{Float64}, T_B <: Real}) = begin
                    TEST(a, b, 3)
                end
        end
        begin
            TEST(a, b, c) = begin
                    TEST(AutoParameters.convert(AbstractArray{Float64}, a), AutoParameters.convert(Real, b), AutoParameters.convert(Int, c))
                end
        end
        begin
            _CreateTEST(bird = TEST; a = [1, 2, 3], b, c = 3) = begin
                    bird(a, b, c)
                end
            ((::(Type){baboon})(; bee...) where baboon <: TEST) = begin
                    _CreateTEST(baboon; bee...)
                end
        end
        const AUTOPARM_TEST_defaults = Dict{Symbol, Any}(:a => (()->begin
                                [1, 2, 3]
                            end), :c => (()->begin
                                3
                            end))
    end
end
```
