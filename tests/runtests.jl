using Test
using AutoParameters


@AutoParm mutable struct TEST
    arr::AUTO <: AbstractArray{Float64} = [1,2,3]
    unknown
    real::AUTO <: Real
    int::Int = 3
    thing::AUTO = "something"
end

@testset "General" begin
    @test_throws UndefKeywordError TEST()
    @test_throws UndefKeywordError TEST(unknown=nothing)
    @test_throws MethodError TEST(unknown=nothing, real="asdf")
    @test_throws InexactError TEST(unknown=nothing, real=5, arr=[1im])

    obj = TEST(unknown=nothing, real=3)

    @test collect(typeof(obj).parameters) == [Vector{Float64}, Int, String]
    @test fieldtypes(typeof(obj)) == (Vector{Float64}, Any, Int, Int, String)

    @test_throws MethodError obj.thing = nothing

    @test_throws TypeError TEST{Any,Any,Any}(unknown=nothing, real=3)

    general_obj = TEST{AbstractArray{Float64},Real,Any}(unknown=nothing, real=3)
    general_obj.thing = nothing
end

@testset "Default arguments" begin
    @test_throws MethodError TEST([1.0], nothing)
    TEST([1.0], nothing, 0)

    # This should work, by converting the input argument automatically.
    @test_broken TEST([1], nothing, 0)
end


# Define an arbitrary constructor that can hide the base constructor
TEST(; common) = _CreateTEST(arr=[common], unknown=common, real=common)
@testset "Defining constructor" begin
    handcrafted = TEST(common=5)
    fallback = TEST([5], 5, 5, 3, "something")

    @test collect(fieldvalues(handcrafted)) == collect(fieldvalues(fallback))
end

# This creates an instance of TEST with the widest types as parameters.
function TEST(; kwds...)
    thetype = TEST
    while !isconcretetype(thetype)
        thetype = thetype{thetype.var.ub}
    end

    thetype(; kwds...)
end

@testset "Defining general then specifying" begin
    general = TEST(unknown=nothing, real=1.0)
    @test typeof(general) == TEST{AbstractArray{Float64}, Real, Any}
    @test typeof(general.arr) == Vector{Float64}
    @test typeof(general.real) == Float64
    @test typeof(general.thing) == String

    general.arr = ones(5,5)
    general.thing = nothing
    general.real = 0

    # Note: this will call the original constructor with all types.
    specific = TEST(fieldvalues(general)...)
    @test typeof(specific) == TEST{Matrix{Float64}, Int, Nothing}
    @test typeof(specific.arr) == Matrix{Float64}
    @test typeof(specific.real) == Int
    @test typeof(specific.thing) == Nothing
end
