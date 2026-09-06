# ---------------------------------------------------------------------------
# Small shared utilities: date handling and input validation.
# ---------------------------------------------------------------------------

using Dates

"""Today's date in the app's local day (server-local time)."""
today_local() = Dates.today()

"""ISO string (YYYY-MM-DD) for `today + offset` days; offset 0 = today."""
function iso_offset(offset::Int)::String
    Dates.format(Dates.today() + Dates.Day(offset), dateformat"yyyy-mm-dd")
end

"""
    normalize_iso_date(raw::AbstractString) -> Union{Nothing,String}

Validates and normalizes a date string submitted by a form. Empty input maps
to `nothing`; anything that is not a valid `YYYY-MM-DD` date throws.
"""
function normalize_iso_date(raw::AbstractString)
    s = strip(raw)
    isempty(s) && return nothing
    d = tryparse(Date, s, dateformat"yyyy-mm-dd")
    d === nothing && throw(ArgumentError("'$s' is not a valid date."))
    Dates.format(d, dateformat"yyyy-mm-dd")
end

"""Parse an ISO date string stored in the DB into a Dates.Date (nothing-safe)."""
function parse_stored_date(v)::Union{Date,Nothing}
    v === nothing && return nothing
    v === missing && return nothing
    d = tryparse(Date, String(v), dateformat"yyyy-mm-dd")
    d
end

"""Days from today until `iso_date` (positive = future). nothing-safe."""
function days_until(iso_date)::Union{Int,Nothing}
    d = parse_stored_date(iso_date)
    d === nothing && return nothing
    Dates.value(d - Dates.today())
end

const EMAIL_RE = r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"

"""True when `email` looks like a valid email address."""
function valid_email(email::AbstractString)::Bool
    occursin(EMAIL_RE, strip(email))
end

"""Normalizes a form-submitted email (trim + lowercase domain part stays intact)."""
function normalize_email(raw::AbstractString)::String
    strip(raw)
end
