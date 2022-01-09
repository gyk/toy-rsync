using Test
using Random: randstring

using ToyRsync

@testset "Checksum" begin
    using ToyRsync:
        weak_checksum,
        weak_checksum_and_state,
        weak_checksum_vec,
        rolling_checksum

    len = BLOCK_SIZE * 4
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
            (a, b) = rolling_checksum((a, b), (old, new), BLOCK_SIZE)
            reinterpret(UInt8, [hton(UInt32(b) << 16 | a)])
        end

        @test h1 == h2 == h3
    end
end

@testset "Smoke" begin
    # NOTE: Need padding if the length is not a multiple of block size.
    src_data = randstring(BLOCK_SIZE * 4)
    println(src_data[1+1:16+1], " ... ", src_data[(end - 16 + 1):end])
    src = IOBuffer(src_data)

    dst_data = copy(Vector{UInt8}(src_data))
    dst_data[BLOCK_SIZE + 1] = UInt8('A')
    dst_data[BLOCK_SIZE + 2] = UInt8('B')
    dst_data[BLOCK_SIZE * 2 + 1] = UInt8('S')
    dst_data[BLOCK_SIZE * 2 + 2] = UInt8('T')
    dst_data[BLOCK_SIZE * 3 + 1] = UInt8('X')
    dst_data[BLOCK_SIZE * 3 + 2] = UInt8('Y')
    dst_data[BLOCK_SIZE * 3 + 3] = UInt8('Z')
    dst = IOBuffer(dst_data)

    hashes = compute_hashes(src)
    seek(src, 1)
    delta = compute_delta(src, hashes)

    out = IOBuffer()
    seek(src, 1)
    patch_delta(src, out, delta)

    dst_data = String(take!(out))
    println(dst_data[1:16], " ... ", dst_data[(end - 16 + 1):end])

    @test true # FIXME
end
