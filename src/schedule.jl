# Planning state shared by the dispatcher, the analytic evaluator and the optimizers.
#
# Execution model (identical in the simulation and in this analytic replay):
# - freight i is released at `ready_s` and assigned immediately (or rejected when
#   no vehicle can carry its weight);
# - every vehicle executes its freights one at a time in release order (FIFO);
# - a trip starts at max(release time, time the vehicle is back at base), drives
#   current location -> pickup -> delivery -> base;
# - lateness = max(0, delivered_at - due_s).

"""
    FleetState

Where a vehicle will be (`lat`, `lon`) and when it will be free (`free_at`) once
it has finished everything assigned to it so far.
"""
mutable struct FleetState
    free_at::Float64
    lat::Float64
    lon::Float64
end

initial_fleet(inst::Instance) = [FleetState(0.0, v.start_lat, v.start_lon) for v in inst.vehicles]

can_carry(v::Vehicle, f::Freight) = v.capacity_kg >= f.weight_kg

"""
    plan_trip(v, state, f) -> (start_s, trip)

Start time and legs if freight `f` is appended to vehicle `v`'s queue.
"""
plan_trip(v::Vehicle, s::FleetState, f::Freight) = (max(f.ready_s, s.free_at), Trip(v, f, s.lat, s.lon))

function commit!(s::FleetState, v::Vehicle, start_s::Float64, trip::Trip)
    s.free_at = start_s + total_s(trip)
    s.lat, s.lon = v.base_lat, v.base_lon
    return s
end

"""
    evaluate_plan(inst, assignment; weights=ObjectiveWeights()) -> NamedTuple

Fast analytic evaluation of an assignment (`assignment[i]` = vehicle index for
freight `i` in instance order, 0 = unserved). Returns the same KPIs as the
discrete-event simulation; the test suite checks that both agree.
"""
function evaluate_plan(inst::Instance, assignment::AbstractVector{<:Integer}; weights::ObjectiveWeights = ObjectiveWeights())
    fleet = initial_fleet(inst)
    m = length(inst.vehicles)
    km = zeros(m)
    busy = zeros(m)
    handled = zeros(Int, m)
    lateness = 0.0
    max_late = 0.0
    n_on_time = 0
    n_unserved = 0
    for (i, f) in enumerate(inst.freights)
        j = assignment[i]
        if j == 0
            n_unserved += 1
            continue
        end
        v = inst.vehicles[j]
        start, trip = plan_trip(v, fleet[j], f)
        late = max(0.0, start + until_delivery_s(trip) - f.due_s)
        lateness += late
        max_late = max(max_late, late)
        n_on_time += late == 0.0
        km[j] += total_km(trip)
        busy[j] += total_s(trip)
        handled[j] += 1
        commit!(fleet[j], v, start, trip)
    end
    makespan = maximum((s.free_at for (s, h) in zip(fleet, handled) if h > 0); init = 0.0)
    return kpis(
        length(inst.freights),
        n_unserved,
        n_on_time,
        sum(km),
        lateness,
        max_late,
        makespan,
        busy,
        weights,
    )
end

"""
    kpis(...) -> NamedTuple

Summary metrics reported for every method:
`n_freights, n_served, n_unserved, n_on_time, on_time_rate, total_distance_km,
total_lateness_h, max_lateness_h, makespan_h, mean_utilization, objective`.
Utilization is busy time divided by the makespan (time the last vehicle is back
at base), so it lies in [0, 1].
"""
function kpis(n, n_unserved, n_on_time, total_km_, lateness_s, max_late_s, makespan_s, busy_s, w::ObjectiveWeights)
    n_served = n - n_unserved
    lateness_h = lateness_s / 3600
    return (
        n_freights = n,
        n_served = n_served,
        n_unserved = n_unserved,
        n_on_time = n_on_time,
        on_time_rate = n == 0 ? 1.0 : n_on_time / n,
        total_distance_km = total_km_,
        total_lateness_h = lateness_h,
        max_lateness_h = max_late_s / 3600,
        makespan_h = makespan_s / 3600,
        mean_utilization = makespan_s > 0 ? sum(busy_s) / (makespan_s * length(busy_s)) : 0.0,
        objective = w.km * total_km_ + w.lateness_per_hour * lateness_h + w.unserved * n_unserved,
    )
end

"""
    assignment_vector(inst, assignment::AbstractDict) -> Vector{Int}

Convert freight id => vehicle id (or `nothing`) into vehicle indices in instance order.
Throws if a vehicle id is unknown or a vehicle cannot carry the freight.
"""
function assignment_vector(inst::Instance, assignment::AbstractDict)
    vidx = Dict(v.id => j for (j, v) in enumerate(inst.vehicles))
    return map(inst.freights) do f
        vid = get(assignment, f.id, nothing)
        vid === nothing && return 0
        j = get(vidx, string(vid)) do
            throw(ArgumentError("unknown vehicle $(vid) for freight $(f.id)"))
        end
        can_carry(inst.vehicles[j], f) ||
            throw(ArgumentError("vehicle $(vid) cannot carry freight $(f.id) ($(f.weight_kg) kg)"))
        j
    end
end

assignment_dict(inst::Instance, a::AbstractVector{<:Integer}) = Dict{String,Union{String,Nothing}}(
    f.id => (a[i] == 0 ? nothing : inst.vehicles[a[i]].id) for (i, f) in enumerate(inst.freights)
)
