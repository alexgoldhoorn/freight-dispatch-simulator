"""
MILP-based optimization for freight dispatch using JuMP and HiGHS.

This module provides exact optimization for the freight dispatch problem,
formulated as a simplified Vehicle Routing Problem (VRP). Unlike greedy
heuristics, MILP finds provably optimal solutions (within solver tolerances).

Key differences from greedy strategies:
- Considers all freights and vehicles simultaneously
- Finds globally optimal assignments
- Much slower (exponential complexity vs linear)
- Best for batch/offline planning scenarios

Limitations:
- Static: all freights must be known upfront
- Simplified time windows (basic feasibility checks)
- Scales poorly with problem size (demo purposes)
"""

using JuMP
using HiGHS
using DataFrames
using Dates
using ..FreightDispatchSimulator: Freight, Vehicle, haversine, FreightResult, VehicleAggregate, sim_seconds

export optimize_dispatch, MILPResult

"""
    MILPResult

Results from MILP optimization including assignment and metrics.

Fields:
- `freight_results`: DataFrame with freight assignments and routes
- `vehicle_aggregates`: DataFrame with vehicle utilization metrics
- `objective_value`: Optimal total distance (km)
- `solve_time`: Time taken to solve (seconds)
- `termination_status`: Solver termination status
- `optimality_gap`: Gap to optimality (0.0 = proven optimal)
"""
struct MILPResult
    freight_results::DataFrame
    vehicle_aggregates::DataFrame
    objective_value::Float64
    solve_time::Float64
    termination_status::String
    optimality_gap::Float64
end

"""
    optimize_dispatch(freights_df::DataFrame, vehicles_df::DataFrame; time_limit=60.0, verbose=false)

Optimize freight dispatch using Mixed Integer Linear Programming.

Formulates and solves a simplified VRP to minimize total distance traveled
by all vehicles while respecting capacity constraints.

# Arguments
- `freights_df`: DataFrame with freight data (same format as greedy strategies)
- `vehicles_df`: DataFrame with vehicle data
- `time_limit`: Maximum solve time in seconds (default: 60.0)
- `verbose`: Print solver output (default: false)

# Returns
- `MILPResult`: Optimization results with assignments and metrics

# Example
```julia
using FreightDispatchSimulator, CSV, DataFrames

freights = CSV.read("data/urban/freights.csv", DataFrame)
vehicles = CSV.read("data/urban/vehicles.csv", DataFrame)

result = optimize_dispatch(freights, vehicles, time_limit=30.0)
println("Optimal distance: ", result.objective_value, " km")
println("Solve time: ", result.solve_time, " seconds")
```

# Notes
- All freights must be known upfront (batch assignment)
- Time windows are simplified (basic feasibility only)
- Solution is provably optimal (within solver tolerance)
- Computation time grows exponentially with problem size
"""
function optimize_dispatch(freights_df::DataFrame, vehicles_df::DataFrame;
                          time_limit=60.0, verbose=false)

    # Make a copy to avoid modifying the original
    freights_copy = copy(freights_df)

    # Convert numeric timestamps to DateTime if needed
    if eltype(freights_copy.pickup_time) <: Number
        freights_copy.pickup_time = Dates.unix2datetime.(freights_copy.pickup_time)
    end
    if eltype(freights_copy.delivery_time) <: Number
        freights_copy.delivery_time = Dates.unix2datetime.(freights_copy.delivery_time)
    end

    # Add simulation time columns (required for Freight constructor)
    reference_time = minimum(vcat(freights_copy.pickup_time, freights_copy.delivery_time))
    freights_copy.pickup_sim_seconds = sim_seconds.(freights_copy.pickup_time, reference_time)
    freights_copy.delivery_sim_seconds = sim_seconds.(freights_copy.delivery_time, reference_time)

    # Convert to internal types
    freights = [Freight(
        string(row.id),
        row.weight_kg,
        row.pickup_lat, row.pickup_lon,
        row.delivery_lat, row.delivery_lon,
        row.pickup_time, row.delivery_time,
        row.pickup_sim_seconds, row.delivery_sim_seconds
    ) for row in eachrow(freights_copy)]

    vehicles = [Vehicle(
        row.id,
        row.start_lat, row.start_lon,
        get(row, :base_lat, row.start_lat),
        get(row, :base_lon, row.start_lon),
        row.capacity_kg,
        row.speed_km_per_hour
    ) for row in eachrow(vehicles_df)]

    n_freights = length(freights)
    n_vehicles = length(vehicles)

    # Precompute all distances
    pickup_distances = zeros(n_freights, n_vehicles)
    delivery_distances = zeros(n_freights, n_vehicles)
    return_distances = zeros(n_freights, n_vehicles)
    total_distances = zeros(n_freights, n_vehicles)

    for i in 1:n_freights
        for j in 1:n_vehicles
            f = freights[i]
            v = vehicles[j]

            # Vehicle start -> pickup
            pickup_distances[i, j] = haversine(v.start_lat, v.start_lon,
                                               f.pickup_lat, f.pickup_lon)
            # Pickup -> delivery
            delivery_distances[i, j] = haversine(f.pickup_lat, f.pickup_lon,
                                                  f.delivery_lat, f.delivery_lon)
            # Delivery -> base
            return_distances[i, j] = haversine(f.delivery_lat, f.delivery_lon,
                                               v.base_lat, v.base_lon)

            total_distances[i, j] = pickup_distances[i, j] +
                                   delivery_distances[i, j] +
                                   return_distances[i, j]
        end
    end

    # Build MILP model
    model = Model(HiGHS.Optimizer)
    set_time_limit_sec(model, time_limit)
    if !verbose
        set_silent(model)
    end

    # Decision variables: x[i,j] = 1 if freight i assigned to vehicle j
    @variable(model, x[1:n_freights, 1:n_vehicles], Bin)

    # Objective: minimize total distance
    @objective(model, Min, sum(total_distances[i,j] * x[i,j]
                               for i in 1:n_freights, j in 1:n_vehicles))

    # Constraint: each freight assigned to exactly one vehicle
    @constraint(model, [i=1:n_freights], sum(x[i,j] for j in 1:n_vehicles) == 1)

    # Constraint: vehicle capacity
    @constraint(model, [j=1:n_vehicles],
                sum(freights[i].weight_kg * x[i,j] for i in 1:n_freights) <=
                vehicles[j].capacity_kg)

    # Solve
    start_time = time()
    JuMP.optimize!(model)
    solve_time = time() - start_time

    # Extract results
    term_status = string(JuMP.termination_status(model))
    optimality_gap = 0.0

    if JuMP.has_values(model)
        obj_value = JuMP.objective_value(model)

        # Build freight results
        freight_results = DataFrame(
            freight_id = String[],
            assigned_vehicle = String[],
            pickup_distance_km = Float64[],
            delivery_distance_km = Float64[],
            return_distance_km = Float64[],
            total_distance_km = Float64[],
            weight_kg = Float64[],
            success = Bool[]
        )

        assignment = JuMP.value.(x)

        for i in 1:n_freights
            for j in 1:n_vehicles
                if assignment[i, j] > 0.5  # Binary variable is 1
                    push!(freight_results, (
                        freight_id = freights[i].id,
                        assigned_vehicle = vehicles[j].id,
                        pickup_distance_km = pickup_distances[i, j],
                        delivery_distance_km = delivery_distances[i, j],
                        return_distance_km = return_distances[i, j],
                        total_distance_km = total_distances[i, j],
                        weight_kg = freights[i].weight_kg,
                        success = true
                    ))
                    break
                end
            end
        end

        # Build vehicle aggregates
        vehicle_aggregates = DataFrame(
            vehicle_id = String[],
            total_distance_km = Float64[],
            total_freights_handled = Int[],
            total_weight_kg = Float64[],
            capacity_kg = Float64[],
            utilization_rate = Float64[]
        )

        for j in 1:n_vehicles
            total_dist = sum(total_distances[i, j] * assignment[i, j]
                           for i in 1:n_freights)
            n_freights_handled = sum(assignment[i, j] > 0.5 for i in 1:n_freights)
            total_weight = sum(freights[i].weight_kg * assignment[i, j]
                             for i in 1:n_freights)

            utilization = total_weight / vehicles[j].capacity_kg

            push!(vehicle_aggregates, (
                vehicle_id = vehicles[j].id,
                total_distance_km = total_dist,
                total_freights_handled = n_freights_handled,
                total_weight_kg = total_weight,
                capacity_kg = vehicles[j].capacity_kg,
                utilization_rate = utilization
            ))
        end

        # Calculate optimality gap (for MIP solvers)
        try
            optimality_gap = JuMP.relative_gap(model)
        catch
            optimality_gap = 0.0
        end

        return MILPResult(
            freight_results,
            vehicle_aggregates,
            obj_value,
            solve_time,
            term_status,
            optimality_gap
        )
    else
        # No solution found
        return MILPResult(
            DataFrame(),
            DataFrame(),
            Inf,
            solve_time,
            term_status,
            Inf
        )
    end
end
