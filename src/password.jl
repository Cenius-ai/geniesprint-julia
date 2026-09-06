# PasswordHasher: salted, iterated PBKDF2-HMAC-SHA256 with constant-time comparison.
#
# Storage format (kept in two separate user columns per the schema):
#   password_salt = 16 random bytes, hex encoded (32 chars)
#   password_hash = 32-byte derived key, hex encoded (64 chars)
#
# The iteration count is stored as a constant in the codebase (never a user
# input), so the two columns stay exactly as the data model describes them.
module PasswordHasher

using SHA
using Random

export PBKDF2_ITERATIONS, SALT_BYTES, hash_password, verify_password, secure_equals

const PBKDF2_ITERATIONS = 60_000   # OWASP 2023 floor for PBKDF2-HMAC-SHA256 is 600k;
                                   # 60k keeps an interactive login snappy on the demo box
                                   # while remaining iterated + salted (never a bare digest).
const SALT_BYTES = 16
const KEY_BYTES = 32

"""
    pbkdf2_sha256(password::AbstractString, salt::Vector{UInt8}, iterations::Int, dklen::Int) -> Vector{UInt8}

RFC 8018 PBKDF2 with HMAC-SHA256 as the pseudo-random function (stdlib `SHA`).
"""
function pbkdf2_sha256(password::AbstractString, salt::Vector{UInt8}, iterations::Int, dklen::Int = KEY_BYTES)::Vector{UInt8}
    password_bytes = Vector{UInt8}(codeunits(password))
    hlen = 32 # SHA-256 output length in bytes
    blocks = cld(dklen, hlen)
    out = UInt8[]

    for block_index in 1:blocks
        # U1 = PRF(password, salt || INT_32_BE(block_index))
        block = UInt8[]
        append!(block, salt)
        push!(block, UInt8((block_index >> 24) & 0xff), UInt8((block_index >> 16) & 0xff),
                    UInt8((block_index >> 8) & 0xff), UInt8(block_index & 0xff))
        u = hmac_sha256(password_bytes, block)
        t = copy(u)
        for _ in 2:iterations
            u = hmac_sha256(password_bytes, u)
            t = xor_bytes(t, u)
        end
        append!(out, t)
    end

    out[1:dklen]
end

function xor_bytes(a::Vector{UInt8}, b::Vector{UInt8})::Vector{UInt8}
    length(a) == length(b) || throw(ArgumentError("xor lengths differ"))
    [x ⊻ y for (x, y) in zip(a, b)]
end

"""
    hash_password(password::AbstractString) -> NamedTuple{(:hash, :salt)}

Generates a fresh 16-byte salt and returns the hex-encoded derived key plus the
hex-encoded salt. The plaintext password is never kept.
"""
function hash_password(password::AbstractString)::NamedTuple{(:hash, :salt)}
    salt = rand(UInt8, SALT_BYTES)
    dk = pbkdf2_sha256(password, salt, PBKDF2_ITERATIONS)
    (hash = bytes2hex(dk), salt = bytes2hex(salt))
end

"""
    verify_password(password::AbstractString, expected_hash::AbstractString, salt_hex::AbstractString) -> Bool

Recomputes the key for `password` with the stored salt and compares against the
stored hash in constant time.
"""
function verify_password(password::AbstractString, expected_hash::AbstractString, salt_hex::AbstractString)::Bool
    isempty(expected_hash) && return false
    isempty(salt_hex) && return false

    try
        salt = hex2bytes(salt_hex)
        expected = hex2bytes(expected_hash)
        computed = pbkdf2_sha256(password, salt, PBKDF2_ITERATIONS)
        return secure_equals(computed, expected)
    catch
        return false
    end
end

"""
    secure_equals(a::AbstractVector{UInt8}, b::AbstractVector{UInt8}) -> Bool

Constant-time byte-string comparison: always walks the whole buffer and never
short-circuits on the first differing byte.
"""
function secure_equals(a::AbstractVector{UInt8}, b::AbstractVector{UInt8})::Bool
    length(a) == length(b) || return false
    diff = 0x00
    for i in eachindex(a)
        diff |= a[i] ⊻ b[i]
    end
    diff == 0x00
end

# Convenience overload for the CSRF token comparison (hex strings).
function secure_equals(a::AbstractString, b::AbstractString)::Bool
    ca = codeunits(a)
    cb = codeunits(b)
    length(ca) == length(cb) || return false
    diff = 0x00
    for i in 1:length(ca)
        diff |= ca[i] ⊻ cb[i]
    end
    diff == 0x00
end

end # module PasswordHasher
