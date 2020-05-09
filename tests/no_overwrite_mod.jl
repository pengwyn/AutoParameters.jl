module no_overwrite_mod

using AutoParameters

@AutoParm mutable struct NO_TYPES
    a = 3.
    b::Int = 0
    c::Int = 0
end

@AutoParm mutable struct ONE_AUTO
    a::AUTO = 3.
    b::Int = 0
    c::Int = 0
end

@AutoParm mutable struct NO_DEFAULTS
    a
    b
    c
end

@AutoParm mutable struct NO_DEFAULTS_WITH_AUTO
    a::AUTO
    b::AUTO
    c
end

end
