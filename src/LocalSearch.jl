# Local search metaheuristic
#
# Starts from a greedy assignment and repeatedly applies the first improving move
# until none is left (a local optimum) or a limit is hit:
#   - relocate: move one freight to another vehicle that can carry it
#   - swap:     exchange the vehicles of two freights
# Candidate assignments are scored with the fast analytic evaluator
# (`evaluate_plan`), which follows the same execution rules as the simulation;
# the final assignment is replayed through the simulation.

"""
    local_search_optimize(freights, vehicles; initial=DistanceStrategy(), weights=ObjectiveWeights(),
                          max_iterations=10_000, time_limit=30.0) -> DispatchResult

Improve an initial solution with relocate and swap moves. `initial` is a
`DispatchStrategy` or a previous `DispatchResult` for the same instance.
`info` holds `initial_objective`, `improvement_pct`, `iterations` and
`local_optimum` (false if a limit stopped the search).
"""
function local_search_optimize(
    inst::Instance;
    initial = DistanceStrategy(),
    weights::ObjectiveWeights = ObjectiveWeights(),
    max_iterations::Integer = 10_000,
    time_limit::Real = 30.0,
)
    t0 = time()
    init = initial isa DispatchResult ? initial : simulate(inst, initial; weights = weights)
    a = assignment_vector(inst, init.assignment)
    n, m = length(inst.freights), length(inst.vehicles)
    carriers = [[j for j in 1:m if can_carry(inst.vehicles[j], f)] for f in inst.freights]

    score(a) = evaluate_plan(inst, a; weights = weights).objective
    initial_objective = score(a)
    current = initial_objective
    iterations = 0
    local_optimum = false
    ε = 1e-9 * max(1.0, abs(initial_objective))

    while iterations < max_iterations && time() - t0 < time_limit
        improved = false
        # Relocate (including serving a previously unserved freight)
        for i in 1:n, j in carriers[i]
            j == a[i] && continue
            old = a[i]
            a[i] = j
            s = score(a)
            if s < current - ε
                current, improved = s, true
                break
            end
            a[i] = old
        end
        # Swap
        if !improved
            for i in 1:n, k in i+1:n
                (a[i] == a[k] || a[i] == 0 || a[k] == 0) && continue
                (a[k] in carriers[i] && a[i] in carriers[k]) || continue
                a[i], a[k] = a[k], a[i]
                s = score(a)
                if s < current - ε
                    current, improved = s, true
                    break
                end
                a[i], a[k] = a[k], a[i]
            end
        end
        improved || (local_optimum = true; break)
        iterations += 1
    end

    info = (
        initial_method = init.method,
        initial_objective = initial_objective,
        improvement_pct = initial_objective > 0 ? 100 * (initial_objective - current) / initial_objective : 0.0,
        iterations = iterations,
        local_optimum = local_optimum,
    )
    return evaluate_assignment(inst, assignment_dict(inst, a); method = "LocalSearch", weights = weights, solve_time_s = time() - t0 + init.solve_time_s, info = info)
end

local_search_optimize(freights::DataFrame, vehicles::DataFrame; kw...) = local_search_optimize(load_instance(freights, vehicles); kw...)
local_search_optimize(x; kw...) = local_search_optimize(load_instance(x); kw...)
