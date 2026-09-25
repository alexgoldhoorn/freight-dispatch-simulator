# Core data structures and instance loading

"""
    Freight

A transport order. Times are in seconds relative to the instance reference time.

- `ready_s`: release time — the order becomes known and can be dispatched
  (CSV column `pickup_time`).
- `due_s`: delivery deadline (CSV column `delivery_time`). Delivering later is
  allowed but counts as lateness.
"""
struct Freight
    id::String
    weight_kg::Float64
    pickup_lat::Float64
    pickup_lon::Float64
    delivery_lat::Float64
    delivery_lon::Float64
    ready_s::Float64
    due_s::Float64
end

"""
    Vehicle

A vehicle with a start location (where it is at time 0) and a base it returns to
after every trip. `base_*` defaults to the start location.
"""
struct Vehicle
    id::String
    start_lat::Float64
    start_lon::Float64
    base_lat::Float64
    base_lon::Float64
    capacity_kg::Float64
    speed_km_per_hour::Float64
end

Vehicle(id, start_lat, start_lon, capacity_kg, speed_km_per_hour) =
    Vehicle(string(id), start_lat, start_lon, start_lat, start_lon, capacity_kg, speed_km_per_hour)

starts_at_base(v::Vehicle) = v.start_lat == v.base_lat && v.start_lon == v.base_lon

"""
    Instance

A problem instance: freights sorted by release time (ties keep input order) and
vehicles in input order. Both orders are part of the model: the dispatcher sees
freights in this order and every vehicle executes its trips in this order.
"""
struct Instance
    freights::Vector{Freight}
    vehicles::Vector{Vehicle}
    reference_time::Union{Dates.DateTime,Nothing}
end

"""
    Trip

One freight carried by one vehicle: drive from the vehicle's current location to
pickup, to delivery, then back to base. Distances in km, times in seconds.
"""
struct Trip
    pickup_km::Float64
    delivery_km::Float64
    return_km::Float64
    pickup_s::Float64
    delivery_s::Float64
    return_s::Float64
end

total_km(t::Trip) = t.pickup_km + t.delivery_km + t.return_km
total_s(t::Trip) = t.pickup_s + t.delivery_s + t.return_s
until_delivery_s(t::Trip) = t.pickup_s + t.delivery_s

function Trip(v::Vehicle, f::Freight, from_lat::Real, from_lon::Real)
    p = haversine(from_lat, from_lon, f.pickup_lat, f.pickup_lon)
    d = haversine(f.pickup_lat, f.pickup_lon, f.delivery_lat, f.delivery_lon)
    r = haversine(f.delivery_lat, f.delivery_lon, v.base_lat, v.base_lon)
    s = v.speed_km_per_hour
    return Trip(p, d, r, travel_time_s(p, s), travel_time_s(d, s), travel_time_s(r, s))
end

"""
    ObjectiveWeights(; km=1.0, lateness_per_hour=100.0, unserved=10_000.0)

Weights of the single objective used by every method:

    objective = km * total_km + lateness_per_hour * total_lateness_h + unserved * n_unserved
"""
Base.@kwdef struct ObjectiveWeights
    km::Float64 = 1.0
    lateness_per_hour::Float64 = 100.0
    unserved::Float64 = 10_000.0
end

"""
    DispatchResult

Outcome of any method (greedy, local search, MILP), always measured by replaying
the assignment through the discrete-event simulation.

- `method`: name of the method
- `assignment`: freight id => vehicle id (`nothing` if unserved)
- `freight_results`, `vehicle_aggregates`: per-freight and per-vehicle tables
- `kpis`: summary metrics (see [`kpis`](@ref))
- `solve_time_s`: wall-clock time spent deciding the assignment
- `info`: method-specific details (e.g. solver status)
"""
struct DispatchResult
    method::String
    assignment::Dict{String,Union{String,Nothing}}
    freight_results::DataFrame
    vehicle_aggregates::DataFrame
    kpis::NamedTuple
    solve_time_s::Float64
    info::NamedTuple
end

function Base.show(io::IO, r::DispatchResult)
    k = r.kpis
    print(
        io,
        "DispatchResult($(r.method): objective=$(round(k.objective; digits=1)), ",
        "km=$(round(k.total_distance_km; digits=1)), served=$(k.n_served)/$(k.n_freights), ",
        "on_time=$(k.n_on_time), lateness_h=$(round(k.total_lateness_h; digits=2)))",
    )
end

# ---------------------------------------------------------------------------
# Loading

_to_datetime(x::Dates.DateTime) = x
_to_datetime(x::Real) = Dates.unix2datetime(x)

function _time_columns(freights::DataFrame)
    pickup = freights.pickup_time
    delivery = freights.delivery_time
    if eltype(pickup) <: Real && eltype(delivery) <: Real
        # Plain seconds: shift so that the earliest release is t = 0
        t0 = minimum(pickup)
        return Float64.(pickup .- t0), Float64.(delivery .- t0), nothing
    end
    p = _to_datetime.(pickup)
    d = _to_datetime.(delivery)
    t0 = minimum(p)
    return sim_seconds.(p, t0), sim_seconds.(d, t0), t0
end

"""
    load_instance(freights::DataFrame, vehicles::DataFrame) -> Instance
    load_instance(dir::AbstractString) -> Instance

Build an [`Instance`](@ref) without modifying the input tables. `pickup_time` and
`delivery_time` may be seconds or `DateTime`s; they are shifted so the earliest
release is at t = 0. `dir` must contain `freights.csv` and `vehicles.csv`.
"""
function load_instance(freights::DataFrame, vehicles::DataFrame)
    nrow(vehicles) > 0 || throw(ArgumentError("at least one vehicle is required"))
    ready, due, t0 = nrow(freights) > 0 ? _time_columns(freights) : (Float64[], Float64[], nothing)

    fs = [
        Freight(
            string(row.id),
            row.weight_kg,
            row.pickup_lat,
            row.pickup_lon,
            row.delivery_lat,
            row.delivery_lon,
            ready[i],
            due[i],
        ) for (i, row) in enumerate(eachrow(freights))
    ]
    # Stable sort: ties in release time keep input order
    fs = fs[sortperm([f.ready_s for f in fs]; alg = Base.Sort.DEFAULT_STABLE)]

    has_base = hasproperty(vehicles, :base_lat) && hasproperty(vehicles, :base_lon)
    vs = map(eachrow(vehicles)) do row
        base_lat = has_base && !ismissing(row.base_lat) ? row.base_lat : row.start_lat
        base_lon = has_base && !ismissing(row.base_lon) ? row.base_lon : row.start_lon
        Vehicle(
            string(row.id),
            row.start_lat,
            row.start_lon,
            base_lat,
            base_lon,
            row.capacity_kg,
            row.speed_km_per_hour,
        )
    end

    length(unique(f.id for f in fs)) == length(fs) || throw(ArgumentError("duplicate freight ids"))
    length(unique(v.id for v in vs)) == length(vs) || throw(ArgumentError("duplicate vehicle ids"))
    return Instance(fs, vs, t0)
end

function load_instance(dir::AbstractString)
    freights = CSV.read(joinpath(dir, "freights.csv"), DataFrame)
    vehicles = CSV.read(joinpath(dir, "vehicles.csv"), DataFrame)
    return load_instance(freights, vehicles)
end

load_instance(inst::Instance) = inst
