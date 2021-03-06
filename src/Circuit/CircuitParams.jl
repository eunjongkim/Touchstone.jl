abstract type CircuitParams{T<:Real} <: AbstractParams end

"""
    Impedance{T<:Real} <: CircuitParams{T}
"""
mutable struct Impedance{T<:Real} <: CircuitParams{T}
    data::Complex{T}
end
Impedance(z::T) where {T<:Real} = Impedance(complex(z))

Impedance(zd::AbstractVector{Complex{T}}) where {T<:Real} =
    [Impedance(zd_) for zd_ in zd]
Impedance(zd::AbstractVector{T}) where {T<:Real} = Impedance(Complex{T}.(zd))

"""
    Admittance{T<:Real} <: CircuitParams{T}
"""
mutable struct Admittance{T<:Real} <: CircuitParams{Real}
    data::Complex{T}
end
Admittance(y::T) where {T<:Real} = Admittance(complex(y))

Admittance(yd::AbstractVector{Complex{T}}) where {T<:Real} =
    [Admittance(yd_) for yd_ in yd]
Admittance(yd::AbstractVector{T}) where {T<:Real} = Admittance(Complex{T}.(yd))

function show(io::IO, params::CircuitParams)
    write(io, "$(typeof(params)): $(params.data)")
end
