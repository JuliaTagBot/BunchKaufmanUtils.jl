module BunchKaufmanUtils

using LinearAlgebra, StaticArrays

export pseudosolve

# Piracy, move to StaticArrays
struct SBunchKaufman{N,T,DT,UT} <: Factorization{T}
    p::SVector{N,Int}
    D::DT
    U::UT
end

function Base.invperm(a::StaticVector{N,Int}) where N
    n = length(a)
    b = MVector{N,Int}(zeros(Int, n))
    @inbounds for (i, j) in enumerate(a)
        ((1 <= j <= n) && b[j] == 0) ||
            throw(ArgumentError("argument is not a permutation"))
        b[j] = i
    end
    return b
end

function LinearAlgebra.bunchkaufman(A::SMatrix{N,N,T}, rook::Bool=false; check=true) where {N,T}
    F = bunchkaufman(Matrix(A), rook; check=check)
    D, U = F.D, F.U
    return SBunchKaufman{N,eltype(F),typeof(D),typeof(U)}(SVector{N,Int}(F.p), D, U)
end

function LinearAlgebra.:\(F::SBunchKaufman{N}, B::Union{StaticVector{N},StaticMatrix{N}}) where N
    X = F.U' \ (F.D \ (F.U \ permrows(B, invperm(F.p))))
    return similar_type(B, eltype(X))(permrows(X, F.p))
end

function pseudosolve(F::Union{BunchKaufman,SBunchKaufman}, B::AbstractVecOrMat; tol=sqrt(eps(eltype(F))))
    D, U, p = F.D, F.U, F.p
    n = size(D, 1)
    Y = U \ permrows(B, invperm(p))
    dthresh = tol*maximum(abs.(D.d))
    i = 1
    while i <= n
        if i == n || iszero(D.du[i])
            solve1!(Y, i, D.d[i], dthresh)
            i += 1
        else
            solve2!(Y, i, D.d[i], D.du[i], D.d[i+1], dthresh)
            i += 2
        end
    end
    X = U' \ Y
    return simtype(B, eltype(X))(permrows(X, p))
end

## Utilities
permrows(v::AbstractVector, p) = v[p]
permrows(M::AbstractMatrix, p) = M[p,:]

simtype(B, ::Type{T}) where T = identity
simtype(B::StaticArray, ::Type{T}) where T = similar_type(B, T)

function solve1!(y::AbstractVector, i, d, dthresh)
    if abs(d) >= dthresh
        y[i] /= d
    else
        y[i] = 0
    end
    return y
end

function solve1!(Y::AbstractMatrix, i, d, dthresh)
    if abs(d) >= dthresh
        for j in eachindex(Y, 2)
            Y[i,j] /= d
        end
    else
        for j in eachindex(Y, 2)
            Y[i,j] = 0
        end
    end
    return Y
end

function solve2!(y::AbstractVector, i, di, dui, di1, dthresh)
    λ1, λ2, V = symeig(di, dui, di1)
    y2 = SVector(y[i], y[i+1])
    vy = V*y2
    dinvvy = SVector(abs(λ1) >= dthresh ? vy[1]/λ1 : zero(eltype(vy)),
                     abs(λ2) >= dthresh ? vy[2]/λ2 : zero(eltype(vy)))
    x = V'*dinvvy
    y[i], y[i+1] = x
    return y
end

function solve2!(Y::AbstractMatrix, i, di, dui, di1, dthresh)
    λ1, λ2, V = symeig(di, dui, di1)
    for j in eachindex(Y, 2)
        y2 = SVector(Y[i,j], Y[i+1,j])
        vy = V*y2
        dinvvy = SVector(abs(λ1) >= dthresh ? vy[1]/λ1 : zero(eltype(vy)),
                         abs(λ2) >= dthresh ? vy[2]/λ2 : zero(eltype(vy)))
        x = V'*dinvvy
        Y[i,j], Y[i+1,j] = x
    end
    return Y
end

function symeig(a, b, d)
    @assert !iszero(b)
    T, D = a + d, a*d-b^2
    if T >= 0
        λ1 = T/2 + sqrt((a-d)^2/4 + b^2)
        λ2 = D/λ1
    else
        λ2 = T/2 - sqrt((a-d)^2/4 + b^2)
        λ1 = D/λ2
    end
    V = @SMatrix [λ1-d b; b λ2-a]
    return λ1, λ2, V
end

end # module
