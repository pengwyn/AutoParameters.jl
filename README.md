# AutoParameters.jl
A combination of automatic parameterised types and default values for structs

Use `@AutoParm` in front of a struct. This will create a default keyword-only constructor and a pure value constructor. A backup `_Create<name>` is also created to allow for overwriting of the default keyword-only constructor.

The default values can also be accessed through `AUTOPARM_<name>_defaults`.

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

The generated code looks like:

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
