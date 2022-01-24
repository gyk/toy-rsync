using Test
using Random: randstring

using ToyRsync

include("mutation.jl")

@testset "Checksum" begin
    using ToyRsync:
        weak_checksum,
        weak_checksum_and_state,
        weak_checksum_vec,
        rolling_checksum

    BLOCK_SIZE = 128
    N_BLOCKS = 32
    len = BLOCK_SIZE * N_BLOCKS
    r = RsyncContext(BLOCK_SIZE)
    data = rand(UInt8, len)
    (x, a, b) = weak_checksum_and_state(@view data[1:BLOCK_SIZE])

    using ToyRsync: weak_checksum_impl, weak_checksum_vec_impl

    for i in 1:(len - BLOCK_SIZE + 1)
        block = @view data[i:(i + BLOCK_SIZE - 1)]
        h1 = weak_checksum(block)
        h2 = weak_checksum_vec(block)

        h3 = if i == 1
            h1
        else
            old = get(data, i - 1, UInt8(0))
            new = get(data, i - 1 + BLOCK_SIZE, UInt8(0))
            (a, b) = rolling_checksum(r, (a, b), (old, new))
            reinterpret(UInt8, [hton(UInt32(b) << 16 | a)])
        end

        @test h1 == h2 == h3
    end
end

@testset "Smoke" begin
    BLOCK_SIZE = 128
    N_BLOCKS = 64
    N_MUTATIONS = 4

    r = RsyncContext(BLOCK_SIZE)

    # NOTE: Need padding if the length is not a multiple of block size.
    src_data = randstring(BLOCK_SIZE * N_BLOCKS)
    println("Src = ", src_data[1:16], " ... ", src_data[(end - 16 + 1):end])
    src = IOBuffer(src_data)

    dst_data = copy(Vector{UInt8}(src_data))

    mutations = rand([Insert, Delete, Replace], N_MUTATIONS)
    println("Mutations = $mutations")
    for m in mutations
        mutate!(r, dst_data, m)
    end

    dst = IOBuffer(dst_data)

    hashes = compute_hashes(r, dst)
    seek(dst, 0)
    src = IOBuffer(src_data)

    delta = compute_delta(r, src, hashes)
    println(delta)

    out = IOBuffer()
    seek(dst, 0)
    patch_delta(r, dst, out, delta)

    dst_data2 = String(take!(out))
    println("Dst = ", dst_data2[1:16], " ... ", dst_data2[(end - 16 + 1):end])

    @test src_data == dst_data2
end
