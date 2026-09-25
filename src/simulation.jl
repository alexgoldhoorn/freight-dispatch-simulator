# Discrete-event simulation (ConcurrentSim.jl)
#
# One dispatcher process releases freights at their ready time and asks the
# strategy for a vehicle. Each vehicle is a process with a FIFO inbox; it takes
# one freight at a time, drives to pickup, delivery and back to base. All
# results are recorded by the vehicle processes (what actually happened), not by
# the dispatcher (what it planned).

# Everything recorded during one run; no global state.
struct SimLog
    assigned::Vector{Int}               # vehicle index per freight, 0 = unserved
    start_s::Vector{Float64}
    pickup_s::Vector{Float64}
    delivered_s::Vector{Float64}
    back_s::Vector{Float64}
    trips::Vector{Union{Trip,Nothing}}
end

SimLog(n::Int) = SimLog(zeros(Int, n), fill(NaN, n), fill(NaN, n), fill(NaN, n), fill(NaN, n), Vector{Union{Trip,Nothing}}(nothing, n))

@resumable function _dispatcher(env::ConcurrentSim.Environment, inst::Instance, strategy::DispatchStrategy, inboxes, log::SimLog)
    fleet = initial_fleet(inst)
    for (i, f) in enumerate(inst.freights)
        t = ConcurrentSim.now(env)
        if t < f.ready_s
            @yield ConcurrentSim.timeout(env, f.ready_s - t)
        end
        j = choose_vehicle(strategy, inst, fleet, i, ConcurrentSim.now(env))
        if j === nothing
            @debug "No vehicle can carry freight" freight = f.id
            continue
        end
        start, trip = plan_trip(inst.vehicles[j], fleet[j], f)
        commit!(fleet[j], inst.vehicles[j], start, trip)
        log.assigned[i] = j
        @debug "Assigned" freight = f.id vehicle = inst.vehicles[j].id t = ConcurrentSim.now(env)
        @yield put!(inboxes[j], i)
    end
end

@resumable function _vehicle(env::ConcurrentSim.Environment, inst::Instance, j::Int, inbox, log::SimLog)
    v = inst.vehicles[j]
    lat, lon = v.start_lat, v.start_lon
    while true
        i = @yield take!(inbox)
        f = inst.freights[i]
        trip = Trip(v, f, lat, lon)
        log.start_s[i] = ConcurrentSim.now(env)
        log.trips[i] = trip
        @yield ConcurrentSim.timeout(env, trip.pickup_s)
        log.pickup_s[i] = ConcurrentSim.now(env)
        @yield ConcurrentSim.timeout(env, trip.delivery_s)
        log.delivered_s[i] = ConcurrentSim.now(env)
        @yield ConcurrentSim.timeout(env, trip.return_s)
        log.back_s[i] = ConcurrentSim.now(env)
        lat, lon = v.base_lat, v.base_lon
    end
end

function _run_des(inst::Instance, strategy::DispatchStrategy)
    n = length(inst.freights)
    log = SimLog(n)
    env = ConcurrentSim.Simulation()
    inboxes = [ConcurrentSim.QueueStore{Int}(env) for _ in inst.vehicles]
    for j in eachindex(inst.vehicles)
        ConcurrentSim.Process(_vehicle, env, inst, j, inboxes[j], log)
    end
    ConcurrentSim.Process(_dispatcher, env, inst, strategy, inboxes, log)
    ConcurrentSim.run(env)
    return log
end

function _tables(inst::Instance, log::SimLog, weights::ObjectiveWeights)
    n, m = length(inst.freights), length(inst.vehicles)
    km, busy, handled = zeros(m), zeros(m), zeros(Int, m)
    rows = map(enumerate(inst.freights)) do (i, f)
        j = log.assigned[i]
        trip = log.trips[i]
        served = j != 0
        served && trip === nothing && error("freight $(f.id) was assigned but never executed")
        late = served ? max(0.0, log.delivered_s[i] - f.due_s) : 0.0
        if served
            km[j] += total_km(trip)
            busy[j] += total_s(trip)
            handled[j] += 1
        end
        (
            freight_id = f.id,
            assigned_vehicle = served ? inst.vehicles[j].id : missing,
            success = served,
            weight_kg = f.weight_kg,
            pickup_lat = f.pickup_lat,
            pickup_lon = f.pickup_lon,
            delivery_lat = f.delivery_lat,
            delivery_lon = f.delivery_lon,
            ready_s = f.ready_s,
            due_s = f.due_s,
            start_s = served ? log.start_s[i] : missing,
            pickup_s = served ? log.pickup_s[i] : missing,
            delivered_s = served ? log.delivered_s[i] : missing,
            back_at_base_s = served ? log.back_s[i] : missing,
            lateness_s = served ? late : missing,
            on_time = served && late == 0.0,
            distance_km = served ? total_km(trip) : 0.0,
        )
    end
    freight_results = DataFrame(rows)

    back = [maximum((log.back_s[i] for i in 1:n if log.assigned[i] == j); init = 0.0) for j in 1:m]
    makespan = maximum(back; init = 0.0)
    vehicle_aggregates = DataFrame(
        vehicle_id = [v.id for v in inst.vehicles],
        total_distance_km = km,
        total_busy_time_s = busy,
        total_freights_handled = handled,
        utilization_rate = makespan > 0 ? busy ./ makespan : zeros(m),
    )

    served = log.assigned .!= 0
    late = [served[i] ? max(0.0, log.delivered_s[i] - inst.freights[i].due_s) : 0.0 for i in 1:n]
    k = kpis(
        n,
        count(!, served),
        count(i -> served[i] && late[i] == 0.0, 1:n),
        sum(km),
        sum(late),
        maximum(late; init = 0.0),
        makespan,
        busy,
        weights,
    )
    return freight_results, vehicle_aggregates, k
end

"""
    simulate(instance, strategy; weights=ObjectiveWeights()) -> DispatchResult

Run the discrete-event simulation with an online `strategy`. `instance` can be an
[`Instance`](@ref), a directory with `freights.csv`/`vehicles.csv`, or use
`simulate(freights_df, vehicles_df, strategy)`.
"""
function simulate(inst::Instance, strategy::DispatchStrategy; weights::ObjectiveWeights = ObjectiveWeights(), method::AbstractString = strategy_name(strategy), solve_time_s = nothing, info::NamedTuple = NamedTuple())
    t = time()
    log = _run_des(inst, strategy)
    elapsed = time() - t
    fr, va, k = _tables(inst, log, weights)
    assignment = assignment_dict(inst, log.assigned)
    return DispatchResult(method, assignment, fr, va, k, something(solve_time_s, elapsed), info)
end

simulate(x, strategy::DispatchStrategy; kw...) = simulate(load_instance(x), strategy; kw...)
simulate(freights::DataFrame, vehicles::DataFrame, strategy::DispatchStrategy; kw...) =
    simulate(load_instance(freights, vehicles), strategy; kw...)

"""
    evaluate_assignment(instance, assignment; kw...) -> DispatchResult

Replay a fixed assignment (freight id => vehicle id or `nothing`) through the
same simulation used for the greedy strategies. This is the single evaluator
that makes all methods comparable.
"""
function evaluate_assignment(inst::Instance, assignment::AbstractDict; method::AbstractString = "FixedAssignment", kw...)
    assignment_vector(inst, assignment)  # validates ids and capacities
    a = Dict{String,Union{String,Nothing}}(string(k) => (v === nothing ? nothing : string(v)) for (k, v) in assignment)
    return simulate(inst, FixedAssignment(a); method = method, kw...)
end

"""
    Simulation(freights, vehicles, strategy=FCFSStrategy()) -> (freight_results, vehicle_aggregates)

Convenience wrapper around [`simulate`](@ref) that returns only the two tables.
The input DataFrames are not modified.
"""
function Simulation(freights::DataFrame, vehicles::DataFrame, strategy::DispatchStrategy = FCFSStrategy())
    r = simulate(freights, vehicles, strategy)
    return r.freight_results, r.vehicle_aggregates
end

function Simulation(freights::DataFrame, vehicles::DataFrame, ::Real, strategy::DispatchStrategy = FCFSStrategy())
    Base.depwarn(
        "`Simulation(freights, vehicles, buffer, strategy)` is deprecated: the simulation now runs until every vehicle is back at base. Use `Simulation(freights, vehicles, strategy)` or `simulate`.",
        :Simulation,
    )
    return Simulation(freights, vehicles, strategy)
end
