"""
An rsync prototype in Julia. Based on https://github.com/isislovecruft/pyrsync.
"""

module ToyRsync

export
    BLOCK_SIZE,
    BlockDiff,
    RsyncHashes,
    apply_diff!,
    compute_delta,
    compute_hashes,
    patch_delta

using SHA: sha256

const BLOCK_SIZE = 4096

strong_checksum = sha256

struct RsyncHashes
    weak::Vector{Vector{UInt8}}
    strong::Vector{Vector{UInt8}}
end

function compute_hashes(s::IO)::RsyncHashes
    weak = Vector{UInt8}[]
    strong = Vector{UInt8}[]
    while !eof(s)
        block = read(s, BLOCK_SIZE)
        push!(weak, weak_checksum(block))
        push!(strong, strong_checksum(block))
    end
    RsyncHashes(weak, strong)
end

# ===== Diff =====

abstract type BlockDiff end

struct Duplicate <: BlockDiff
    i::Int
end

struct Literal <: BlockDiff
    data::Vector{UInt8}
end

function apply_diff!(s::IO, diff::Duplicate)::Vector{UInt8}
    seek!(s, diff.i)
    read(s, BLOCK_SIZE)
end

function apply_diff!(_s::IO, diff::Literal)::Vector{UInt8}
    diff.data
end

# ===== Delta =====

struct RsyncDelta
    diffs::Vector{BlockDiff}
end

function compute_delta(src::IO, hashes::RsyncHashes)::RsyncDelta
    diffs = BlockDiff[]

    start_i::Int = 1
    while !eof(src)
        block = read(src, BLOCK_SIZE)
        weak = weak_checksum_vec(block)
        matched_i = findnext(isequal(weak), hashes.weak, start_i)
        if !isnothing(matched_i) && strong_checksum(block) == hashes.strong[matched_i]
            push!(diffs, Duplicate(matched_i))
            start_i = matched_i + 1
        else
            push!(diffs, Literal(block))
        end
    end

    RsyncDelta(diffs)
end

function patch_delta(in_s::IO, out_s::IO, delta::RsyncDelta)
    for diff in delta.diffs
        patched_block = apply_diff!(in_s, diff)
        write(out_s, patched_block)
    end
end

# ===== Block operations =====

@inline function weak_checksum(block::AbstractVector{UInt8})::Vector{UInt8}
    (x, _, _) = weak_checksum_impl(block)
    reinterpret(UInt8, [hton(x)])
end

@inline function weak_checksum_and_state(
    block::AbstractVector{UInt8}
)::Tuple{Vector{UInt8}, UInt32, UInt32}
    (x, a, b) = weak_checksum_impl(block)
    x = reinterpret(UInt8, [hton(x)])
    (x, a, b)
end

const M = UInt32(65521)

# NOTE: Do NOT define a and b as `UInt16` because `+` might overflow.

function weak_checksum_impl(block::AbstractVector{UInt8})::Tuple{UInt32, UInt32, UInt32}
    a = UInt32(1)
    b = UInt32(0)
    for x in block
        a = (a + x) % M
        b = (b + a) % M
    end
    (UInt32(b) << 16 | a, UInt32(a), UInt32(b))
end

@inline function weak_checksum_vec(block::AbstractVector{UInt8})::Vector{UInt8}
    x = weak_checksum_vec_impl(block)
    reinterpret(UInt8, [hton(x)])
end

# It won't overflow for common block sizes.
function weak_checksum_vec_impl(block::AbstractVector{UInt8})::UInt32
    n = length(block)
    a = mod(1 + sum(block), M)
    b = mod(n + sum(block .* (n:-1:1)), M)
    UInt32(b) << 16 | a
end

#====

Derive rolling checksum of Adler-32:

(mod 65521)

A =  1 + D_1 + D_2 + ... + D_n
A' = 1       + D_2 + ... + D_n + D_{n+1}

B = (1 + D_1) + (1 + D_1 + D_2) + ... + (1 + D_1 + D_2 + ... + D_n)
  = n × D_1 + (n-1) × D_2 + (n-2) × D_3 + ... + D_n + n

B' = n × D2 + (n-1) × D_3 + ... + 2 × D_n + D_{n+1} + n
   = B + (D_2 + D_3 + ... + D_n) + D_{n+1} - n × D_1
   = B + (A' - 1 - D_{n+1}) + D_{n+1} - n × D_1
   = B + A' - 1 - n × D_1

====#

function rolling_checksum(
    (a, b)::Tuple{UInt32, UInt32},
    (old, new)::Tuple{UInt8, UInt8},
    block_size::Int,
)::Tuple{UInt32, UInt32}
    a = mod(UInt32(a) + new + M - old, M)
    b = mod(b + a + M - UInt32(1) - mod(UInt32(old) * UInt32(block_size), M), M)
    (a, b)
end

end # module
