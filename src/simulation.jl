# Main simulation orchestration

"""
    Simulation(freights::DataFrame, vehicles::DataFrame, return_to_base_buffer::Float64, strategy::DispatchStrategy)

Run a freight dispatch simulation with the specified strategy.

# Arguments
- `freights::DataFrame`: DataFrame containing freight information with columns:
  - `id`: Freight identifier
  - `weight_kg`: Weight in kilograms
  - `pickup_lat`, `pickup_lon`: Pickup coordinates
  - `delivery_lat`, `delivery_lon`: Delivery coordinates
  - `pickup_time`, `delivery_time`: Time windows (numeric or DateTime)
- `vehicles::DataFrame`: DataFrame containing vehicle information with columns:
  - `id`: Vehicle identifier
  - `start_lat`, `start_lon`: Starting coordinates
  - `capacity_kg`: Capacity in kilograms
  - `speed_km_per_hour`: Travel speed
  - `base_lat`, `base_lon`: Base coordinates (optional)
- `return_to_base_buffer::Float64`: Additional time buffer (seconds) after last delivery
- `strategy::DispatchStrategy`: Dispatch strategy to use (FCFS, Cost, Distance, OverallCost)

# Returns
- `freight_results_df::DataFrame`: Results for each freight including:
  - `freight_id`: Freight identifier
  - `assigned_vehicle`: Assigned vehicle ID (or nothing)
  - `pickup_time`: Pickup timestamp
  - `delivery_time`: Delivery timestamp
  - `completion_time`: Total completion time
  - `distance_km`: Total distance traveled
  - `success`: Whether delivery succeeded
- `vehicle_aggregates_df::DataFrame`: Aggregate statistics for each vehicle including:
  - `vehicle_id`: Vehicle identifier
  - `total_distance_km`: Total distance traveled
  - `total_busy_time_s`: Total busy time
  - `total_freights_handled`: Number of freights handled
  - `utilization_rate`: Utilization rate (0-1)

# Example
```julia
using FreightDispatchSimulator
using CSV, DataFrames

freights_df = CSV.read("freights.csv", DataFrame)
vehicles_df = CSV.read("vehicles.csv", DataFrame)

freight_results, vehicle_aggregates = Simulation(
    freights_df,
    vehicles_df,
    3600.0,  # 1 hour buffer
    DistanceStrategy()
)
```
"""
function Simulation(
    freights::DataFrame,
    vehicles::DataFrame,
    return_to_base_buffer::Float64 = 3600.0,
    strategy::DispatchStrategy = FCFSStrategy(),
)
    # Clear previous results
    empty!(FREIGHT_RESULTS)
    empty!(VEHICLE_AGGREGATES)

    # Initialize simulation
    sim = SimJulia.Simulation()
    println("Starting simulation...")

    # Convert numeric timestamps to DateTime if needed
    if eltype(freights.pickup_time) <: Number
        freights.pickup_time = Dates.unix2datetime.(freights.pickup_time)
    end
    if eltype(freights.delivery_time) <: Number
        freights.delivery_time = Dates.unix2datetime.(freights.delivery_time)
    end

    # Find the earliest and latest timestamps to use as reference
    reference_time = minimum(vcat(freights.pickup_time, freights.delivery_time))
    max_delivery_time = maximum(freights.delivery_time)

    # Convert all timestamps to simulation seconds relative to reference
    freights.pickup_sim_seconds = sim_seconds.(freights.pickup_time, reference_time)
    freights.delivery_sim_seconds = sim_seconds.(freights.delivery_time, reference_time)

    # Create Freight objects
    freight_objects = [
        Freight(
            string(freights[i, :id]),
            freights[i, :weight_kg],
            freights[i, :pickup_lat],
            freights[i, :pickup_lon],
            freights[i, :delivery_lat],
            freights[i, :delivery_lon],
            freights[i, :pickup_time],
            freights[i, :delivery_time],
            freights[i, :pickup_sim_seconds],
            freights[i, :delivery_sim_seconds],
        ) for i = 1:nrow(freights)
    ]

    # Initialize vehicle aggregates
    for i = 1:nrow(vehicles)
        vehicle_id = string(vehicles[i, :id])
        VEHICLE_AGGREGATES[vehicle_id] = VehicleAggregate(vehicle_id, 0.0, 0.0, 0, 0.0)
    end

    # Set up vehicle inboxes and info
    vehicle_inbox = Dict{String,Store{Freight}}()
    vehicles_info = Dict{String,VehicleInfo}()

    for i = 1:nrow(vehicles)
        vehicle_id = string(vehicles[i, :id])
        vehicle_inbox[vehicle_id] = Store{Freight}(sim)

        base_lat = if hasproperty(vehicles, :base_lat)
            vehicles[i, :base_lat]
        else
            vehicles[i, :start_lat]
        end
        base_lon = if hasproperty(vehicles, :base_lon)
            vehicles[i, :base_lon]
        else
            vehicles[i, :start_lon]
        end

        vehicles_info[vehicle_id] = VehicleInfo(
            vehicle_id,
            vehicles[i, :capacity_kg],
            vehicles[i, :speed_km_per_hour],
            0.0,
            vehicles[i, :start_lat],
            vehicles[i, :start_lon],
            base_lat,
            base_lon,
        )

        @process run_vehicle_with_results(
            sim,
            vehicle_id,
            vehicles[i, :start_lat],
            vehicles[i, :start_lon],
            vehicles[i, :capacity_kg],
            vehicles[i, :speed_km_per_hour],
            vehicle_inbox[vehicle_id],
            reference_time,
        )
    end

    # Create ONE dispatcher process
    if length(freight_objects) > 0 && length(vehicle_inbox) > 0
        @process dispatch_freight(
            sim,
            freight_objects,
            vehicle_inbox,
            vehicles_info,
            strategy,
        )
    end

    # Calculate simulation end time: max delivery time + buffer
    simulation_end_time =
        sim_seconds(max_delivery_time, reference_time) + return_to_base_buffer
    println("Running simulation until time: ", simulation_end_time, " seconds")

    # Run simulation until max delivery time + buffer
    run(sim, simulation_end_time)

    # Calculate utilization rates
    total_sim_time = simulation_end_time
    for (vehicle_id, agg) in VEHICLE_AGGREGATES
        agg.utilization_rate = agg.total_busy_time_s / total_sim_time
    end

    # Convert results to DataFrames
    freight_results_df = DataFrame([
        (
            freight_id = r.freight_id,
            assigned_vehicle = r.assigned_vehicle,
            pickup_time = r.pickup_time,
            delivery_time = r.delivery_time,
            completion_time = r.completion_time,
            distance_km = r.distance_km,
            success = r.success,
        ) for r in FREIGHT_RESULTS
    ])

    vehicle_aggregates_df = DataFrame([
        (
            vehicle_id = agg.vehicle_id,
            total_distance_km = agg.total_distance_km,
            total_busy_time_s = agg.total_busy_time_s,
            total_freights_handled = agg.total_freights_handled,
            utilization_rate = agg.utilization_rate,
        ) for agg in values(VEHICLE_AGGREGATES)
    ])

    println(
        "Simulation completed. Processed ",
        length(FREIGHT_RESULTS),
        " freights with ",
        nrow(vehicles),
        " vehicles.",
    )

    return freight_results_df, vehicle_aggregates_df
end
