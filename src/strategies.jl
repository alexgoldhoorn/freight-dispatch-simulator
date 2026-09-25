# Online dispatch strategies (greedy heuristics)
#
# At the release time of each freight the dispatcher asks the strategy for a
# vehicle. Only vehicles that can carry the weight are candidates. A vehicle that
# is still busy can be chosen: the freight then waits in that vehicle's queue.
# Ties are always broken by vehicle order in the input, so runs are deterministic.

"""
    DispatchStrategy

Abstract type for online dispatch rules. Implement
`choose_vehicle(strategy, inst, fleet, freight_index, now_s)` returning a vehicle
index or `nothing` (freight unserved).
"""
abstract type DispatchStrategy end

"""
    FCFSStrategy()

First come, first served: the first idle vehicle in input order; if all are busy,
the vehicle that becomes free first.
"""
struct FCFSStrategy <: DispatchStrategy end

"""
    CostStrategy()

Nearest idle vehicle to the pickup (minimises empty kilometres); if all are busy,
the vehicle that becomes free first.
"""
struct CostStrategy <: DispatchStrategy end

"""
    DistanceStrategy()

Idle vehicle with the shortest full trip (to pickup + delivery + back to base);
if all are busy, the vehicle that becomes free first.
"""
struct DistanceStrategy <: DispatchStrategy end

"""
    OverallCostStrategy()

Vehicle with the earliest estimated delivery time, counting queueing behind
earlier assignments and vehicle speed. Busy vehicles compete with idle ones.
"""
struct OverallCostStrategy <: DispatchStrategy end

"""
    FixedAssignment(assignment::Dict{String,<:Union{String,Nothing}})

Replays a given assignment (freight id => vehicle id, `nothing` = unserved).
Used to evaluate optimizer output in the same simulation as the greedy rules.
"""
struct FixedAssignment <: DispatchStrategy
    assignment::Dict{String,Union{String,Nothing}}
end

strategy_name(::FCFSStrategy) = "FCFS"
strategy_name(::CostStrategy) = "Cost"
strategy_name(::DistanceStrategy) = "Distance"
strategy_name(::OverallCostStrategy) = "OverallCost"
strategy_name(::FixedAssignment) = "FixedAssignment"

"""
    GREEDY_STRATEGIES

Name => strategy for all built-in greedy rules.
"""
const GREEDY_STRATEGIES = [
    "FCFS" => FCFSStrategy(),
    "Cost" => CostStrategy(),
    "Distance" => DistanceStrategy(),
    "OverallCost" => OverallCostStrategy(),
]

# Pick argmin of `key(j)` over candidate vehicles, ties -> lowest index.
function _argmin(key, candidates)
    best, best_key = nothing, nothing
    for j in candidates
        k = key(j)
        if best === nothing || k < best_key
            best, best_key = j, k
        end
    end
    return best
end

_candidates(inst, f) = [j for (j, v) in enumerate(inst.vehicles) if can_carry(v, f)]

function _idle_or_earliest(inst, fleet, f, now_s, idle_key)
    cands = _candidates(inst, f)
    isempty(cands) && return nothing
    idle = [j for j in cands if fleet[j].free_at <= now_s]
    isempty(idle) || return _argmin(idle_key, idle)
    return _argmin(j -> fleet[j].free_at, cands)
end

choose_vehicle(::FCFSStrategy, inst, fleet, i, now_s) =
    _idle_or_earliest(inst, fleet, inst.freights[i], now_s, j -> j)

function choose_vehicle(::CostStrategy, inst, fleet, i, now_s)
    f = inst.freights[i]
    return _idle_or_earliest(inst, fleet, f, now_s, j -> haversine(fleet[j].lat, fleet[j].lon, f.pickup_lat, f.pickup_lon))
end

function choose_vehicle(::DistanceStrategy, inst, fleet, i, now_s)
    f = inst.freights[i]
    return _idle_or_earliest(inst, fleet, f, now_s, j -> total_km(plan_trip(inst.vehicles[j], fleet[j], f)[2]))
end

function choose_vehicle(::OverallCostStrategy, inst, fleet, i, now_s)
    f = inst.freights[i]
    return _argmin(_candidates(inst, f)) do j
        start, trip = plan_trip(inst.vehicles[j], fleet[j], f)
        start + until_delivery_s(trip)
    end
end

function choose_vehicle(s::FixedAssignment, inst, fleet, i, now_s)
    vid = get(s.assignment, inst.freights[i].id, nothing)
    vid === nothing && return nothing
    return findfirst(v -> v.id == vid, inst.vehicles)
end
