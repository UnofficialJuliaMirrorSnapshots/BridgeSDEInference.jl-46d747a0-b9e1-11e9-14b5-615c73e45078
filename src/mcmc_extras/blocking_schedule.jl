import Base: display


"""
    ChequeredBlocking

Struct
```
struct ChequeredBlocking{TP,TWW,TXX} <: BlockingSchedule
    Ls         # observation operators for both sets of blocks
    vs         # copied over observations of the process
    Σs         # covariance matrix of the noise for both sets of blocks
    # two sets of knots
    knots::Tuple{Vector{Int64}, Vector{Int64}}
    # two sets of blocks, where each block are indicies of intervals that make up a block
    blocks::Tuple{Vector{Vector{Int64}}, Vector{Vector{Int64}}}
    idx::Int64 # index of set of blocks that are being updated ∈{1,2}
    accpt::Tuple{Vector{Int64}, Vector{Int64}} # tracker for the number of accepted samples
    props::Tuple{Vector{Int64}, Vector{Int64}} # tracker for the number of proposed samples
    # info about the points at which to switch between the systems of ODEs
    change_pts::Tuple{Vector{ODEChangePt}, Vector{ODEChangePt}}
end
```
is a blocking schedule in which two sets of blocks are defined in an interlacing
manner. For instance, if all knots consist of {1,2,3,4,5,6,7,8,9}, then set A
will contain {1,3,5,7,9}, whereas set B {2,4,6,8}. These knots will then
uniquely determine the blocks

    ChequeredBlocking(knots::Vector{Int64}, ϵ::Float64, change_pt::ODEChangePt,
                      P::TP, WW::TWW, XX::TXX)

Base constructor that takes a set of all `knots` (which it then splits into
two disjoint subsets), the artificial noise parameter `ϵ`, information about
a point at which to switch between ODE solvers for H, Hν, c and L, M⁺, μ, an
object with diffusion laws `P`, container `WW` for the driving Brownian motion,
container `XX` for the sampled path (only the size and type of the latter three
are important, not actual values passed, because they are copied and used
internally as containers).

    ChequeredBlocking(𝔅::ChequeredBlocking{TP̃, TWW, TXX}, P::TP, idx::Int64)

Clone constructor. It creates a new object `ChequeredBlocking` from the old one
`𝔅` by using the same type and size of the containers `WW` and `XX`, but a
changed type of the law `P` (changed from `TP̃` to `TP`). The index of a current
update can also be changed via `idx`.

    ChequeredBlocking()

Empty constructor.
"""
struct ChequeredBlocking <: BlockingSchedule
    Ls         # observation operators for both sets of blocks
    vs         # copied over observations of the process
    Σs         # covariance matrix of the noise for both sets of blocks
    # two sets of knots
    knots::Tuple{Vector{Int64}, Vector{Int64}}
    # two sets of blocks, where each block are indicies of intervals that make up a block
    blocks::Tuple{Vector{Vector{Int64}}, Vector{Vector{Int64}}}
    idx::Int64 # index of set of blocks that are being updated ∈{1,2}
    accpt::Tuple{Vector{Int64}, Vector{Int64}} # tracker for the number of accepted samples
    props::Tuple{Vector{Int64}, Vector{Int64}} # tracker for the number of proposed samples
    # info about the points at which to switch between the systems of ODEs
    change_pts::Tuple{Vector{ODEChangePt}, Vector{ODEChangePt}}

    function ChequeredBlocking(knots::Vector{Int64}, ϵ::Float64,
                               change_pt::ODEChangePt, P)
        find_knots(mod, rem) = [k for (i,k) in enumerate(knots) if i % mod == rem]
        knotsA = find_knots(2, 1)
        knotsB = find_knots(2, 0)

        m, d = size(P[end].L)

        find_L(knots) = [( k in knots ? SMatrix{d,d}(1.0*I) : p.L) for (k,p) in enumerate(P)]
        LsA = find_L(knotsA)
        LsB = find_L(knotsB)

        vs = [p.v for p in P]

        find_Σ(knots) = [(k in knots ? SMatrix{d,d}(ϵ*I) : p.Σ) for (k,p) in enumerate(P)]
        ΣsA = find_Σ(knotsA)
        ΣsB = find_Σ(knotsB)

        find_ch_pt(knots) = [(k in knots ? deepcopy(change_pt) : p.change_pt)
                                                    for (k,p) in enumerate(P)]
        chpA = find_ch_pt(knotsA)
        chpB = find_ch_pt(knotsB)

        """
            knots_to_blocks(knots, idxLast, i)

        Given a list of `knots` fetch the indices of the intervals that together
        make up the `i`-th block. `idxLast` is the index of the last interval.
        """
        function knots_to_blocks(knots, idxLast, i)
            M = length(knots)
            @assert M > 0
            if M >= i > 1
                return (knots[i-1]+1):knots[i]
            elseif i == 1
                return 1:knots[1]
            else
                return (knots[M]+1):idxLast
            end
        end
        blocks = ([collect(knots_to_blocks(knotsA, length(P), i)) for i in 1:length(knotsA)+1],
                  [collect(knots_to_blocks(knotsB, length(P), i)) for i in 1:length(knotsB)+1])

        accpt = (zeros(Int64, length(blocks[1])),
                 zeros(Int64, length(blocks[2])))
        props = (zeros(Int64, length(blocks[1])),
                 zeros(Int64, length(blocks[2])))
        new( (LsA, LsB), vs, (ΣsA, ΣsB), (knotsA, knotsB), blocks, 1, accpt,
             props, (chpA, chpB) )
    end

    function ChequeredBlocking()
        new( nothing, nothing, nothing, ([0],[0]), ([[0]],[[0]]), 1, ([0],[0]),
             ([0],[0]), ([NoChangePt()],[NoChangePt()]) )
    end
end


"""
    find_end_pts(𝔅::ChequeredBlocking, XX, idx)

Determine the observations for the update of the `idx`-th set of blocks. In
particular, on each block with interval indices [a₁,…,aₙ], observations vᵢ with
i∈{1,…,n-1} are made, whereas the last obesrvation is an exactly observed
process Xₜ at the terminal time t of the aₙ-th interval.
"""
function find_end_pts(𝔅::ChequeredBlocking, XX, idx)
    [( k in 𝔅.knots[idx] ? X.yy[end] : 𝔅.vs[k]) for (k,X) in enumerate(XX)]
end


"""
    display(𝔅::NoBlocking)

Nothing particular to display
"""
function display(𝔅::NoBlocking)
    print("No blocking...\n")
end

"""
    display(𝔅::ChequeredBlocking)

Display the pattern of blocks
"""
function display(𝔅::ChequeredBlocking)
    function print_blocks(knots, idxLast, m)
        M = length(knots)
        get_knot(knots, i) = (M >= i > 0 ? knots[i] : idxLast * (i>0))
        function print_range(from, to)
            for i in from:to
                print("|", get_knot(knots,i-1), "|----",
                      get_knot(knots,i)-get_knot(knots,i-1), "----")
            end
        end

        if m > div(M, 2)
            print_range(1, M+1)
            print("|", idxLast, "|")
        else
            print_range(1,m)
            print("|", get_knot(knots, m) ,"|   ...   ")
            print_range(M+2-m,M+1)
            print("|", idxLast, "|")
        end
        print("  (number of blocks: ", M+1,")")
    end
    print("Chequered Blocking scheme\n",
          "-------------------------\n",
          "Format:\n",
          "block sizes in A: ")
    print_blocks(𝔅.knots[1], length(𝔅.vs), 3)
    print("\nblock sizes in B: ")
    print_blocks(𝔅.knots[2], length(𝔅.vs), 3)
    print("\n")
end

"""
    registerAccpt(𝔅::BlockingSchedule, i, accepted)

Register whether the block has been accepted
"""
function register_accpt!(ws, i, accepted)
    𝔅 = ws.blocking
    𝔅.props[ws.blidx][i] += 1
    𝔅.accpt[ws.blidx][i] += 1*accepted
end


"""
    displayAcceptance(𝔅::NoBlocking)

Nothing to display
"""
function display_acceptance_rate(𝔅::NoBlocking) end


"""
    displayAcceptance(𝔅::NoBlocking)

Display acceptance rates
"""
function display_acceptance_rate(𝔅::BlockingSchedule)
    print("\nAcceptance rates:\n----------------------\n")
    function print_accpt_rate(accpt, prop)
        m = length(accpt)
        for i in 1:m
            print("b", i, ": ", accpt[i]/prop[i], " | ")
        end
        print("\n- - - - - - - - - - - - - -\n")
    end
    print_accpt_rate(𝔅.accpt[1], 𝔅.props[1])
    print_accpt_rate(𝔅.accpt[2], 𝔅.props[2])
end








"""
    set_blocking(𝔅::NoBlocking, ::Any, ::Any)

No blocking is to be done, do nothing
"""
set_blocking(𝔅::NoBlocking, ::Any, ::Any) = 𝔅


"""
    set_blocking(::ChequeredBlocking, blockingParams, ws)

Blocking pattern is chosen to be a chequerboard.
"""
function set_blocking(::ChequeredBlocking, blocking_params, P)
    ChequeredBlocking(blocking_params..., P)
end
