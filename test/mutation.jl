using ToyRsync: RsyncContext

abstract type Mutation end

function mutate!(r::RsyncContext, data::Vector{UInt8}, m::Mutation)
    error("Unimplemented")
end

struct Insert <: Mutation end
struct Delete <: Mutation end
struct Replace <: Mutation end

function mutate!(r::RsyncContext, data::Vector{UInt8}, Insert)
    insert_pos = rand(1:length(data))
    insert_len = begin
        l = (r.block_size / 4 + randn() * r.block_size / 2)
        l = round(Int, l)
        max(l, 0)
    end
    insert_data = rand(UInt8, insert_len)

    data = [data[1:(insert_pos - 1)]; insert_data; data[insert_pos:end]]
end

function mutate!(r::RsyncContext, data::Vector{UInt8}, Delete)
    delete_pos = rand(1:length(data))
    delete_len = begin
        l = (r.block_size / 4 + randn() * r.block_size / 2)
        l = round(Int, l)
        clamp(l, 0, length(data) - delete_pos + 1)
    end

    deleteat!(data, delete_pos:min(delete_pos + delete_len - 1, length(data)))
end

function mutate!(r::RsyncContext, data::Vector{UInt8}, Replace)
    replace_pos = rand(1:length(data))
    replace_len = begin
        l = (r.block_size / 4 + randn() * r.block_size / 2)
        l = round(Int, l)
        clamp(l, 0, length(data) - replace_pos + 1)
    end
    replace_data = rand(UInt8, replace_len)

    splice!(data, replace_pos:0, replace_data)
end
