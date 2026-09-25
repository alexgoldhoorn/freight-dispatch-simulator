# Exact optimisation with a MILP (JuMP + HiGHS)
#
# The model optimises the assignment under exactly the same execution rules as
# the simulation (see schedule.jl): one freight per trip, each vehicle serves its
# freights in release order, trips start at max(release, vehicle back at base),
# lateness is penalised, and a freight is unserved only when no vehicle can
# carry it (the same rule the greedy dispatcher follows).
# Therefore the model objective of the optimal assignment equals the objective
# measured by replaying that assignment in the simulation (the tests check this).
#
# Variables (i = freight in release order, j = vehicle able to carry it):
#   x[i,j] ∈ {0,1}  freight i served by vehicle j
#   y[i,j] ∈ {0,1}  i is the first trip of j (only when j does not start at its base)
#   S[i] ≥ ready_i  trip start time,  L[i] ≥ 0  lateness (s)
#
# min  Σ km_b[i,j] x[i,j] + Σ (km_s - km_b)[i,j] y[i,j] + w_late/3600 Σ L[i]  (+ constant for unservable freights)
# s.t. Σ_j x[i,j] = 1   for every freight some vehicle can carry
#      y[i,j] ≤ x[i,j],  y[i,j] ≥ x[i,j] - Σ_{k<i} x[k,j],  y[i,j] + x[k,j] ≤ 1   (k < i)
#      S[i] ≥ S[k] + T[k,j](y) - M (2 - x[k,j] - x[i,j])                          (k < i)
#      L[i] ≥ S[i] + D[i,j](y) - due_i - M (1 - x[i,j])
# where km_b/T/D are trip km, trip time and time-to-delivery from the base, and
# km_s/... the same from the start location (used only for the first trip).

"""
    optimize_dispatch(freights, vehicles; time_limit=60.0, weights=ObjectiveWeights(), verbose=false) -> DispatchResult

Solve the dispatch problem to optimality (or until `time_limit` seconds) with a
MILP that follows the simulation's execution rules exactly. The best greedy
solution is passed as a warm start. The returned result is the best assignment found
replayed through the simulation. `info` holds solver details:
`termination_status`, `proven_optimal`, `relative_gap`, `model_objective`,
`n_variables`, `n_constraints`.

Size: O(n² m) constraints, practical up to roughly 20–30 freights.
"""
function optimize_dispatch(inst::Instance; time_limit::Real = 60.0, weights::ObjectiveWeights = ObjectiveWeights(), verbose::Bool = false)
    t0 = time()
    F, V = inst.freights, inst.vehicles
    n, m = length(F), length(V)

    feas = [(i, j) for i in 1:n for j in 1:m if can_carry(V[j], F[i])]
    needs_first = [!starts_at_base(v) for v in V]
    first_pairs = [(i, j) for (i, j) in feas if needs_first[j]]

    base_trip = Dict((i, j) => Trip(V[j], F[i], V[j].base_lat, V[j].base_lon) for (i, j) in feas)
    start_trip = Dict((i, j) => Trip(V[j], F[i], V[j].start_lat, V[j].start_lon) for (i, j) in feas)

    horizon = maximum((f.ready_s for f in F); init = 0.0) +
              sum((maximum(max(total_s(base_trip[(i, j)]), total_s(start_trip[(i, j)])) for (ii, j) in feas if ii == i; init = 0.0) for i in 1:n); init = 0.0)
    M = 2 * horizon + maximum((abs(f.due_s) for f in F); init = 0.0) + 1.0

    model = Model(HiGHS.Optimizer)
    set_time_limit_sec(model, Float64(time_limit))
    verbose || set_silent(model)

    @variable(model, x[feas], Bin)
    @variable(model, y[first_pairs], Bin)
    @variable(model, S[i = 1:n] >= F[i].ready_s)
    @variable(model, L[1:n] >= 0)

    yv(i, j) = needs_first[j] ? y[(i, j)] : 0.0
    trip_time(i, j) = total_s(base_trip[(i, j)]) + (total_s(start_trip[(i, j)]) - total_s(base_trip[(i, j)])) * yv(i, j)
    to_delivery(i, j) = until_delivery_s(base_trip[(i, j)]) +
                        (until_delivery_s(start_trip[(i, j)]) - until_delivery_s(base_trip[(i, j)])) * yv(i, j)

    by_vehicle = [[i for (i, jj) in feas if jj == j] for j in 1:m]

    servable = [i for i in 1:n if any(p -> p[1] == i, feas)]
    @constraint(model, [i = servable], sum(x[(i, j)] for (ii, j) in feas if ii == i) == 1)
    for (i, j) in first_pairs
        earlier = [k for k in by_vehicle[j] if k < i]
        @constraint(model, y[(i, j)] <= x[(i, j)])
        @constraint(model, y[(i, j)] >= x[(i, j)] - sum((x[(k, j)] for k in earlier); init = 0))
        for k in earlier
            @constraint(model, y[(i, j)] + x[(k, j)] <= 1)
        end
    end
    for j in 1:m, (a, k) in enumerate(by_vehicle[j]), i in by_vehicle[j][a+1:end]
        @constraint(model, S[i] >= S[k] + trip_time(k, j) - M * (2 - x[(k, j)] - x[(i, j)]))
    end
    for (i, j) in feas
        @constraint(model, L[i] >= S[i] + to_delivery(i, j) - F[i].due_s - M * (1 - x[(i, j)]))
    end

    @objective(
        model,
        Min,
        weights.km * (sum((total_km(base_trip[p]) * x[p] for p in feas); init = 0.0) +
                      sum(((total_km(start_trip[p]) - total_km(base_trip[p])) * y[p] for p in first_pairs); init = 0.0)) +
        weights.lateness_per_hour / 3600 * sum(L) +
        weights.unserved * (n - length(servable))
    )

    # Warm start from the best greedy rule
    warm = _best_greedy_assignment(inst, weights)
    _set_warm_start!(inst, warm, x, y, S, L, feas, first_pairs)

    JuMP.optimize!(model)
    status = JuMP.termination_status(model)

    a = if JuMP.has_values(model)
        [something(findfirst(j -> (i, j) in keys(base_trip) && JuMP.value(x[(i, j)]) > 0.5, 1:m), 0) for i in 1:n]
    else
        warm
    end
    info = (
        termination_status = string(status),
        proven_optimal = status == MOI.OPTIMAL,
        relative_gap = JuMP.has_values(model) ? JuMP.relative_gap(model) : NaN,
        model_objective = JuMP.has_values(model) ? JuMP.objective_value(model) : NaN,
        n_variables = JuMP.num_variables(model),
        n_constraints = JuMP.num_constraints(model; count_variable_in_set_constraints = false),
    )
    return evaluate_assignment(inst, assignment_dict(inst, a); method = "MILP", weights = weights, solve_time_s = time() - t0, info = info)
end

optimize_dispatch(freights::DataFrame, vehicles::DataFrame; kw...) = optimize_dispatch(load_instance(freights, vehicles); kw...)
optimize_dispatch(x; kw...) = optimize_dispatch(load_instance(x); kw...)

function _best_greedy_assignment(inst::Instance, weights::ObjectiveWeights)
    best, best_obj = Int[], Inf
    for (_, s) in GREEDY_STRATEGIES
        r = simulate(inst, s; weights = weights)
        a = assignment_vector(inst, r.assignment)
        if r.kpis.objective < best_obj
            best, best_obj = a, r.kpis.objective
        end
    end
    return best
end

function _set_warm_start!(inst, a, x, y, S, L, feas, first_pairs)
    fleet = initial_fleet(inst)
    used = falses(length(inst.vehicles))
    for (i, f) in enumerate(inst.freights)
        j = a[i]
        if j == 0
            set_start_value(S[i], f.ready_s)
            set_start_value(L[i], 0.0)
            continue
        end
        start, trip = plan_trip(inst.vehicles[j], fleet[j], f)
        set_start_value(S[i], start)
        set_start_value(L[i], max(0.0, start + until_delivery_s(trip) - f.due_s))
        (i, j) in first_pairs && set_start_value(y[(i, j)], used[j] ? 0.0 : 1.0)
        used[j] = true
        commit!(fleet[j], inst.vehicles[j], start, trip)
    end
    for (i, j) in feas
        set_start_value(x[(i, j)], a[i] == j ? 1.0 : 0.0)
    end
    for (i, j) in first_pairs
        a[i] == j || set_start_value(y[(i, j)], 0.0)
    end
end
