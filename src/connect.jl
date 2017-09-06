export connect, innerconnect, cascade


check_frequency_identical(ntwkA::NetworkData{T},
    ntwkB::NetworkData{S}) where {T<:NetworkParams, S<:NetworkParams} =
    (ntwkA.frequency == ntwkB.frequency)

check_port_impedance_identical(ntwkA::NetworkData{T}, k,
    ntwkB::NetworkData{S}, l) where {T<:NetworkParams, S<:NetworkParams} =
    (ntwkA.ports[k].impedance == ntwkA.ports[k].impedance)

function connect(ntwkA::NetworkData{T}, k::Int,
    ntwkB::NetworkData{S}, l::Int) where {T<:NetworkParams, S<:NetworkParams}
    ZA, ZB = impedances(ntwkA), impedances(ntwkB)
    ntwkA_S, ntwkB_S = (convert(NetworkData{Sparams}, ntwkA),
        convert(NetworkData{Sparams}, ntwkB))

    if ~check_port_impedance_identical(ntwkA_S, k, ntwkB_S, l)
        stepNetwork = NetworkData([ntwkA_S.ports[k], ntwkB_S.ports[l]],
            ntwkA_S.frequency, [impedance_step(ZA[k], ZB[l]) for n in 1:ntwkA_S.nPoint])
        ntwkA_S_matched = _connect_S(ntwkA_S, k, stepNetwork, 1)
        # renumbering of ports after attaching impedance step
        I_before, I_after = vcat(ntwkA.nPort, k:(ntwkA.nPort-1)), collect(k:(ntwkA.nPort))
        permutePorts!(ntwkA_S_matched, I_before, I_after)
        return connect(ntwkA_S_matched, k, ntwkB_S, l)
    else
        return _connect_S(ntwkA_S, k, ntwkB_S, l)
    end
end

function innerconnect(ntwk::NetworkData{T}, k::Int, l::Int) where {T<:NetworkParams}
    k, l = sort([k, l])
    Z = impedances(ntwk)
    nPort = ntwk.nPort
    ntwk_S = convert(NetworkData{Sparams}, ntwk)
    if ~check_port_impedance_identical(ntwk_S, k, ntwk_S, l)
        stepNetwork = NetworkData([ntwk.ports[k], ntwk.ports[l]], ntwk.frequency,
            [impedance_step(Z[k], Z[l]) for n in 1:ntwk.nPoint])
        ntwk_S_matched = _connect_S(ntwk_S, k, stepNetwork, 1)
        # _connect_S function moves the k-th port to the nPort-th port. Need to
        # permute indices such that the k-th port impedance-matched to the l-th
        # port is located at index k.
        I_before, I_after = vcat(nPort, k:(nPort-1)), collect(k:nPort)
        permutePorts!(ntwk_S_matched, I_before, I_after)
        return innerconnect(ntwk_S_matched, k, l)
    else
        return _innerconnect_S(ntwk_S, k, l)
    end
end

"""
innerconnect two ports (assumed to have same port impedances) of a single n-port
S-parameter network:

              Sₖⱼ Sᵢₗ (1 - Sₗₖ) + Sₗⱼ Sᵢₖ (1 - Sₖₗ) + Sₖⱼ Sₗₗ Sᵢₖ + Sₗⱼ Sₖₖ Sᵢₗ
S′ᵢⱼ = Sᵢⱼ + ----------------------------------------------------------
                            (1 - Sₖₗ) (1 - Sₗₖ) - Sₖₖ Sₗₗ
"""
function _innerconnect_S(ntwk::NetworkData{Sparams}, k::Int, l::Int)
    k, l = sort([k, l])
    nPort, nPoint = ntwk.nPort, ntwk.nPoint
    ports = deepcopy(ntwk.ports)
    deleteat!(ports, [k, l])  # remove ports that are innerconnected
    params = Vector{Sparams}(nPoint)
    newind = vcat(1:(k-1), (k+1):(l-1), (l+1):nPort)
    for n in 1:nPoint
        tmp = zeros(Complex128, (nPort, nPort))
        S = ntwk.params[n].data
        for i in newind, j in 1:newind
            tmp[i, j] = S[i, j] +
                (S[k, j] * S[i, l] * (1 - S[l, k]) +
                 S[l, j] * S[i, k] * (1 - S[k, l]) +
                 S[k, j] * S[l, l] * S[i, k] +
                 S[l, j] * S[k, k] * S[i, l]) /
                ((1 - S[k, l]) * (1 - S[l, k]) - S[k, k] * S[l, l])
        end
        params[n] = Sparams(tmp[newind, newind])
    end
    return NetworkData(ports, ntwk.frequency, params)
end

"""
Connect two
"""
function _connect_S(A::NetworkData{Sparams}, k::Int,
    B::NetworkData{Sparams}, l::Int)
    nA, nB = A.nPort, B.nPort
    nPoint = (A.frequency == B.frequency)? A.nPoint : error("")
    portsA, portsB = deepcopy(A.ports), deepcopy(B.ports)
    ports = vcat(portsA, portsB)
    # Create a supernetwork containing `A` and `B`
    params = Vector{Sparams}(nPoint)
    for n in 1:nPoint
        tmp = zeros(Complex128, (nPort, nPort))
        tmp[1:nA, 1:nA] = A.params[n].data
        tmp[(nA+1):(nA+nB), (nA+1):(nA+nB)] = B.params[n].data
        params[n] = Sparams(tmp)
    end
    return _innerconnect_S(NetworkData(ports, A.frequency, params), k, nA + l)
end

"""
Cascade a 2-port touchstone data `Data::NetworkData{T}` `N::Int` times
"""
cascade(Data::NetworkData{T}, N::Int) where {T<:TwoPortParams} =
    convert(T, convert(ABCDparams, Data) ^ N)

"""
Terminate port 2 of a two-port network `s::NetworkData{Sparams}`
with a one-port touchstone data `t::NetworkData{Sparams, 1}`

s₁₁′ = s₁₁ + s₂₁t₁₁s₁₂ / (1 - t₁₁s₂₂)
"""
function terminate(s::NetworkData{Sparams}, t::NetworkData{Sparams})
    if (s.nPort != 2) | (t.nPort != 1)
        error("Supported only for the case of a two-port network terminated by a one-port network")
    end
    if (s.frequency != t.frequency) | (s.impedance != t.impedance)
        error("Operations between data of different
            frequencies or characteristic impedances not supported")
    end

    s′_data = zeros(Complex128, (1, 1, s.nPoint))
    s′_data[1, 1, :] = (s.data[1, 1, :] + s.data[2, 1, :] .* t.data[1, 1, :]
        .* s.data[1, 2, :] ./ (1 - t.data[1, 1, :] .* s.data[2, 2, :]))
    return NetworkData(Sparams, 1, s.nPoint, s.impedance, s.frequency, s′_data)
end
"""
Method for
"""
terminate{T<:NetworkParams, S<:NetworkParams}(s::NetworkData{T},
    t::NetworkData{S}) = terminate(convert(Sparams, s), convert(Sparams, t))
