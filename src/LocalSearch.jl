"""
Local Search metaheuristic for freight dispatch.

Improves upon greedy solutions through iterative refinement. Explores the
solution neighborhood by swapping freight assignments between vehicles.

Key characteristics:
- Starts from greedy solution (fast initialization)
- Iteratively explores nearby solutions
- Accepts improvements until local optimum reached
- Typically achieves 1-5% optimality gap (vs 5-10% for pure greedy)
- Solving time: seconds (between greedy milliseconds and MILP minutes)
"""

using DataFrames
using ..FreightDispatchSimulator: Freight, Vehicle, haversine

export local_search_optimize, LocalSearchResult

"""
    LocalSearchResult

Results from local search optimization.

Fields:
- `freight_results`: DataFrame with improved freight assignments
- `vehicle_aggregates`: DataFrame with vehicle utilization metrics
- `objective_value`: Total distance after local search (km)
- `initial_objective`: Initial greedy distance (km)
- `improvement`: Percentage improvement over greedy
- `iterations`: Number of iterations performed
- `solve_time`: Time taken to optimize (seconds)
"""
struct LocalSearchResult
    freight_results::DataFrame
    vehicle_aggregates::DataFrame
    objective_value::Float64
    initial_objective::Float64
    improvement::Float64
    iterations::Int
    solve_time::Float64
end

"""
    local_search_optimize(initial_result, freights_df, vehicles_df; max_iterations=1000, time_limit=30.0)

Improve a greedy solution using local search.

Starts from an initial greedy solution and iteratively explores the neighborhood
by swapping freight assignments between vehicles. Accepts swaps that reduce total
distance until no further improvement is found or limits are reached.

# Arguments
- `initial_result`: Tuple of (freight_results, vehicle_aggregates) from greedy strategy
- `freights_df`: DataFrame with original freight data
- `vehicles_df`: DataFrame with vehicle data
- `max_iterations`: Maximum number of iterations (default: 1000)
- `time_limit`: Maximum optimization time in seconds (default: 30.0)

# Returns
- `LocalSearchResult`: Improved solution with metrics

# Example
```julia
using FreightDispatchSimulator, CSV, DataFrames

freights = CSV.read("data/urban/freights.csv", DataFrame)
vehicles = CSV.read("data/urban/vehicles.csv", DataFrame)

# Start with greedy solution
greedy_result = Simulation(freights, vehicles, 3600.0, DistanceStrategy())

# Improve with local search
improved = local_search_optimize(greedy_result, freights, vehicles, time_limit=10.0)

println("Initial: ", improved.initial_objective, " km")
println("Improved: ", improved.objective_value, " km")
println("Improvement: ", improved.improvement, "%")
```

# Notes
- Requires initial feasible solution (from greedy strategy)
- Best for problem sizes 10-50 freights
- Uses simple swap neighborhood (reassign freight to different vehicle)
- Stops when no improvement found or time/iteration limit reached
"""
function local_search_optimize(
    initial_result::Tuple{DataFrame, DataFrame},
    freights_df::DataFrame,
    vehicles_df::DataFrame;
    max_iterations::Int=1000,
    time_limit::Float64=30.0
)
    start_time = time()

    freight_results, vehicle_aggregates = initial_result

    # Create internal representation
    freights = [Freight(
        string(row.id),
        row.weight_kg,
        row.pickup_lat, row.pickup_lon,
        row.delivery_lat, row.delivery_lon,
        row.pickup_time, row.delivery_time,
        get(row, :pickup_sim_seconds, 0.0),
        get(row, :delivery_sim_seconds, 0.0)
    ) for row in eachrow(freights_df)]

    vehicles = [Vehicle(
        row.id,
        row.start_lat, row.start_lon,
        get(row, :base_lat, row.start_lat),
        get(row, :base_lon, row.start_lon),
        row.capacity_kg,
        row.speed_km_per_hour
    ) for row in eachrow(vehicles_df)]

    # Build freight index
    freight_idx = Dict(f.id => i for (i, f) in enumerate(freights))
    vehicle_idx = Dict(v.id => i for (i, v) in enumerate(vehicles))

    # Current assignment: freight_id => vehicle_id
    current_assignment = Dict(
        row.freight_id => row.assigned_vehicle
        for row in eachrow(freight_results) if row.success
    )

    # Calculate initial objective
    initial_objective = sum(vehicle_aggregates.total_distance_km)
    current_objective = initial_objective

    iterations = 0
    improved = true

    while improved && iterations < max_iterations && (time() - start_time) < time_limit
        improved = false
        iterations += 1

        # Try swapping each freight to each vehicle
        for (freight_id, current_vehicle_id) in current_assignment
            f_idx = freight_idx[freight_id]
            freight = freights[f_idx]
            current_v_idx = vehicle_idx[current_vehicle_id]

            for (new_v_idx, new_vehicle) in enumerate(vehicles)
                new_vehicle_id = new_vehicle.id

                # Skip if same vehicle
                if new_vehicle_id == current_vehicle_id
                    continue
                end

                # Check capacity constraint
                new_vehicle_load = sum(
                    freights[freight_idx[fid]].weight_kg
                    for (fid, vid) in current_assignment
                    if vid == new_vehicle_id
                )

                if new_vehicle_load + freight.weight_kg > new_vehicle.capacity_kg
                    continue
                end

                # Calculate delta in objective
                delta = calculate_delta(
                    freight, freight_id,
                    current_vehicle_id, new_vehicle_id,
                    current_assignment, freights, vehicles,
                    freight_idx, vehicle_idx
                )

                # If improvement found, accept it
                if delta < -0.01  # Small tolerance for floating point
                    current_assignment[freight_id] = new_vehicle_id
                    current_objective += delta
                    improved = true
                    break  # Move to next freight
                end
            end

            if improved
                break  # Restart search from beginning
            end
        end
    end

    solve_time = time() - start_time

    # Build result DataFrames
    final_freight_results = build_freight_results(
        current_assignment, freights, vehicles, freight_idx, vehicle_idx
    )

    final_vehicle_aggregates = build_vehicle_aggregates(
        current_assignment, freights, vehicles, freight_idx, vehicle_idx
    )

    improvement = ((initial_objective - current_objective) / initial_objective) * 100.0

    return LocalSearchResult(
        final_freight_results,
        final_vehicle_aggregates,
        current_objective,
        initial_objective,
        improvement,
        iterations,
        solve_time
    )
end

"""
Calculate change in objective if freight reassigned from old_vehicle to new_vehicle
"""
function calculate_delta(
    freight, freight_id,
    old_vehicle_id, new_vehicle_id,
    assignment, freights, vehicles,
    freight_idx, vehicle_idx
)
    # Old vehicle: calculate current contribution
    old_v = vehicles[vehicle_idx[old_vehicle_id]]
    old_dist_old = calculate_vehicle_distance(old_vehicle_id, assignment, freights, vehicles, freight_idx, vehicle_idx)

    # New vehicle: calculate current contribution
    new_v = vehicles[vehicle_idx[new_vehicle_id]]
    new_dist_old = calculate_vehicle_distance(new_vehicle_id, assignment, freights, vehicles, freight_idx, vehicle_idx)

    # Simulate the swap
    temp_assignment = copy(assignment)
    temp_assignment[freight_id] = new_vehicle_id

    # Calculate new distances
    old_dist_new = calculate_vehicle_distance(old_vehicle_id, temp_assignment, freights, vehicles, freight_idx, vehicle_idx)
    new_dist_new = calculate_vehicle_distance(new_vehicle_id, temp_assignment, freights, vehicles, freight_idx, vehicle_idx)

    # Delta = (new_distances) - (old_distances)
    delta = (old_dist_new + new_dist_new) - (old_dist_old + new_dist_old)

    return delta
end

"""
Calculate total distance traveled by a vehicle given current assignment
"""
function calculate_vehicle_distance(vehicle_id, assignment, freights, vehicles, freight_idx, vehicle_idx)
    v = vehicles[vehicle_idx[vehicle_id]]

    # Get freights assigned to this vehicle
    assigned_freights = [
        freights[freight_idx[fid]]
        for (fid, vid) in assignment
        if vid == vehicle_id
    ]

    if isempty(assigned_freights)
        return 0.0
    end

    total_dist = 0.0

    # Simplified: assume each freight is independent trip from base
    for freight in assigned_freights
        # Start -> pickup -> delivery -> base
        dist = haversine(v.start_lat, v.start_lon, freight.pickup_lat, freight.pickup_lon)
        dist += haversine(freight.pickup_lat, freight.pickup_lon, freight.delivery_lat, freight.delivery_lon)
        dist += haversine(freight.delivery_lat, freight.delivery_lon, v.base_lat, v.base_lon)
        total_dist += dist
    end

    return total_dist
end

"""
Build freight results DataFrame from assignment
"""
function build_freight_results(assignment, freights, vehicles, freight_idx, vehicle_idx)
    results = DataFrame(
        freight_id = String[],
        assigned_vehicle = String[],
        pickup_distance_km = Float64[],
        delivery_distance_km = Float64[],
        return_distance_km = Float64[],
        total_distance_km = Float64[],
        weight_kg = Float64[],
        success = Bool[]
    )

    for (freight_id, vehicle_id) in assignment
        f = freights[freight_idx[freight_id]]
        v = vehicles[vehicle_idx[vehicle_id]]

        pickup_dist = haversine(v.start_lat, v.start_lon, f.pickup_lat, f.pickup_lon)
        delivery_dist = haversine(f.pickup_lat, f.pickup_lon, f.delivery_lat, f.delivery_lon)
        return_dist = haversine(f.delivery_lat, f.delivery_lon, v.base_lat, v.base_lon)
        total_dist = pickup_dist + delivery_dist + return_dist

        push!(results, (
            freight_id = freight_id,
            assigned_vehicle = vehicle_id,
            pickup_distance_km = pickup_dist,
            delivery_distance_km = delivery_dist,
            return_distance_km = return_dist,
            total_distance_km = total_dist,
            weight_kg = f.weight_kg,
            success = true
        ))
    end

    return results
end

"""
Build vehicle aggregates DataFrame from assignment
"""
function build_vehicle_aggregates(assignment, freights, vehicles, freight_idx, vehicle_idx)
    aggregates = DataFrame(
        vehicle_id = String[],
        total_distance_km = Float64[],
        total_freights_handled = Int[],
        total_weight_kg = Float64[],
        capacity_kg = Float64[],
        utilization_rate = Float64[]
    )

    for vehicle in vehicles
        vehicle_id = vehicle.id

        # Get assignments for this vehicle
        assigned = [
            freights[freight_idx[fid]]
            for (fid, vid) in assignment
            if vid == vehicle_id
        ]

        total_dist = calculate_vehicle_distance(vehicle_id, assignment, freights, vehicles, freight_idx, vehicle_idx)
        n_freights = length(assigned)
        total_weight = sum(f.weight_kg for f in assigned; init=0.0)
        utilization = total_weight / vehicle.capacity_kg

        push!(aggregates, (
            vehicle_id = vehicle_id,
            total_distance_km = total_dist,
            total_freights_handled = n_freights,
            total_weight_kg = total_weight,
            capacity_kg = vehicle.capacity_kg,
            utilization_rate = utilization
        ))
    end

    return aggregates
end
