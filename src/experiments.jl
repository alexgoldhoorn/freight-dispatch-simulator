# Comparing methods and generating random instances

"""
    compare_methods(instance; methods=[:greedy, :local_search, :milp], weights=ObjectiveWeights(),
                    milp_time_limit=60.0, ls_time_limit=30.0) -> (table, results)

Run the requested methods on one instance and evaluate all of them in the same
simulation. Returns a summary `DataFrame` (one row per method, including the gap
to the best objective found) and the vector of `DispatchResult`s.
`:greedy` expands to all four greedy rules.
"""
function compare_methods(
    inst::Instance;
    methods = [:greedy, :local_search, :milp],
    weights::ObjectiveWeights = ObjectiveWeights(),
    milp_time_limit::Real = 60.0,
    ls_time_limit::Real = 30.0,
)
    results = DispatchResult[]
    for method in methods
        if method == :greedy
            append!(results, [simulate(inst, s; weights = weights) for (_, s) in GREEDY_STRATEGIES])
        elseif method == :local_search
            greedy = filter(r -> r.method in first.(GREEDY_STRATEGIES), results)
            initial = isempty(greedy) ? DistanceStrategy() : argmin(r -> r.kpis.objective, greedy)
            push!(results, local_search_optimize(inst; initial = initial, weights = weights, time_limit = ls_time_limit))
        elseif method == :milp
            push!(results, optimize_dispatch(inst; weights = weights, time_limit = milp_time_limit))
        else
            throw(ArgumentError("unknown method $(method)"))
        end
    end
    best = minimum(r.kpis.objective for r in results)
    table = DataFrame([
        (
            method = r.method,
            objective = r.kpis.objective,
            gap_to_best_pct = best > 0 ? 100 * (r.kpis.objective - best) / best : 0.0,
            distance_km = r.kpis.total_distance_km,
            served = r.kpis.n_served,
            on_time = r.kpis.n_on_time,
            lateness_h = r.kpis.total_lateness_h,
            makespan_h = r.kpis.makespan_h,
            utilization = r.kpis.mean_utilization,
            solve_time_s = r.solve_time_s,
            proven_optimal = get(r.info, :proven_optimal, missing),
        ) for r in results
    ])
    return table, results
end

compare_methods(freights::DataFrame, vehicles::DataFrame; kw...) = compare_methods(load_instance(freights, vehicles); kw...)
compare_methods(x; kw...) = compare_methods(load_instance(x); kw...)

"""
    generate_instance(n_freights, n_vehicles; seed=1, lat=(41.0, 42.3), lon=(0.8, 3.2),
                      horizon_h=8.0, n_depots=2) -> (freights, vehicles)

Random regional instance (default: Catalonia). Freights are released uniformly
over `horizon_h` hours; each deadline is the direct driving time at 70 km/h
plus 1–4 hours of slack. Vehicles are spread over `n_depots` depots with mixed
capacities. Same `seed` gives the same instance.
"""
function generate_instance(
    n_freights::Integer,
    n_vehicles::Integer;
    seed::Integer = 1,
    lat = (41.0, 42.3),
    lon = (0.8, 3.2),
    horizon_h::Real = 8.0,
    n_depots::Integer = 2,
)
    rng = Random.Xoshiro(seed)
    point() = (lat[1] + rand(rng) * (lat[2] - lat[1]), lon[1] + rand(rng) * (lon[2] - lon[1]))
    depots = [point() for _ in 1:n_depots]
    capacities = [1000.0, 3500.0, 7500.0]

    vehicles = DataFrame(
        id = ["V$(j)" for j in 1:n_vehicles],
        start_lat = [depots[mod1(j, n_depots)][1] for j in 1:n_vehicles],
        start_lon = [depots[mod1(j, n_depots)][2] for j in 1:n_vehicles],
        capacity_kg = [capacities[mod1(j, length(capacities))] for j in 1:n_vehicles],
        speed_km_per_hour = [60.0 + 20.0 * rand(rng) for _ in 1:n_vehicles],
    )

    rows = map(1:n_freights) do i
        (plat, plon), (dlat, dlon) = point(), point()
        ready = round(rand(rng) * horizon_h * 3600)
        direct = travel_time_s(haversine(plat, plon, dlat, dlon), 70.0)
        (
            id = "F$(i)",
            weight_kg = round(100 + rand(rng) * 2900),
            pickup_lat = round(plat; digits = 4),
            pickup_lon = round(plon; digits = 4),
            delivery_lat = round(dlat; digits = 4),
            delivery_lon = round(dlon; digits = 4),
            pickup_time = ready,
            delivery_time = round(ready + direct + (1 + 3 * rand(rng)) * 3600),
        )
    end
    freights = DataFrame(rows)
    sort!(freights, :pickup_time)
    return freights, vehicles
end
