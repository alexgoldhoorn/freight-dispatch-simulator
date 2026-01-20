# Dispatcher logic for assigning freights to vehicles

# Global result collectors (shared across simulation runs)
const FREIGHT_RESULTS = Vector{FreightResult}()
const VEHICLE_AGGREGATES = Dict{String,VehicleAggregate}()

"""
    dispatch_freight(sim, freight_objects, vehicle_inbox, vehicle_info, strategy)

Main dispatcher process that assigns freights to vehicles based on the chosen strategy.
Runs as a SimJulia resumable function (coroutine) during the simulation.

# Arguments
- `sim::SimJulia.Simulation`: The simulation environment
- `freight_objects::Vector{Freight}`: List of freights to dispatch
- `vehicle_inbox::Dict{String,Store{Freight}}`: Communication channels to vehicles
- `vehicle_info::Dict{String,VehicleInfo}`: Vehicle tracking information
- `strategy::DispatchStrategy`: The dispatch strategy to use
"""
@resumable function dispatch_freight(
    sim::SimJulia.Simulation,
    freight_objects::Vector{Freight},
    vehicle_inbox::Dict{String,Store{Freight}},
    vehicle_info::Dict{String,VehicleInfo},
    strategy::DispatchStrategy,
)
    # Strategy selection
    sorted_freights = select_freights(strategy, freight_objects)

    println("Dispatcher: Starting dispatch for ", length(sorted_freights), " freights")

    for freight in sorted_freights
        # Wait until freight pickup time
        current_time = now(sim)
        if current_time < freight.pickup_ts
            wait_time = freight.pickup_ts - current_time
            @yield timeout(sim, wait_time)
        end

        current_time = now(sim)

        # Find the best vehicle based on the chosen strategy
        assigned_vehicle =
            find_best_vehicle(strategy, vehicle_info, vehicle_inbox, freight, current_time)

        if assigned_vehicle !== nothing
            process_assignment(vehicle_info, assigned_vehicle, freight, current_time)
            @yield put(vehicle_inbox[assigned_vehicle], freight)
        else
            handle_failure(freight, current_time)
        end
    end

    println("Dispatcher: All freights processed")
end

"""
    process_assignment(vehicle_info, assigned_vehicle, freight, current_time)

Process a successful freight assignment: calculate metrics and update records.

# Arguments
- `vehicle_info::Dict{String,VehicleInfo}`: Vehicle tracking information
- `assigned_vehicle::String`: ID of the assigned vehicle
- `freight::Freight`: The freight being assigned
- `current_time::Float64`: Current simulation time
"""
function process_assignment(
    vehicle_info::Dict{String,VehicleInfo},
    assigned_vehicle::String,
    freight::Freight,
    current_time::Float64,
)
    println("Dispatcher: Assigning freight ", freight.id, " to vehicle ", assigned_vehicle)
    vehicle = vehicle_info[assigned_vehicle]

    # Calculate distances
    pickup_distance = haversine(
        vehicle.current_lat,
        vehicle.current_lon,
        freight.pickup_lat,
        freight.pickup_lon,
    )
    delivery_distance = haversine(
        freight.pickup_lat,
        freight.pickup_lon,
        freight.delivery_lat,
        freight.delivery_lon,
    )
    return_distance = haversine(
        freight.delivery_lat,
        freight.delivery_lon,
        vehicle.base_lat,
        vehicle.base_lon,
    )

    # Calculate travel times
    pickup_travel_time = pickup_distance / vehicle.speed_km_per_hour * 3600
    delivery_travel_time = delivery_distance / vehicle.speed_km_per_hour * 3600
    return_travel_time = return_distance / vehicle.speed_km_per_hour * 3600
    total_travel_time = pickup_travel_time + delivery_travel_time + return_travel_time
    completion_time = current_time + total_travel_time

    # Update vehicle availability and location
    vehicle.available_at = completion_time
    vehicle.current_lat = vehicle.base_lat
    vehicle.current_lon = vehicle.base_lon

    # Record freight result
    push!(
        FREIGHT_RESULTS,
        FreightResult(
            freight.id,
            assigned_vehicle,
            freight.pickup_ts,
            freight.delivery_ts,
            completion_time,
            pickup_distance + delivery_distance + return_distance,
            true,
        ),
    )

    # Update vehicle aggregates
    agg = VEHICLE_AGGREGATES[assigned_vehicle]
    agg.total_distance_km += pickup_distance + delivery_distance + return_distance
    agg.total_busy_time_s += total_travel_time
    agg.total_freights_handled += 1

    return nothing
end

"""
    handle_failure(freight, current_time)

Record a failed freight assignment when no suitable vehicle is found.

# Arguments
- `freight::Freight`: The freight that could not be assigned
- `current_time::Float64`: Current simulation time
"""
function handle_failure(freight::Freight, current_time::Float64)
    push!(
        FREIGHT_RESULTS,
        FreightResult(
            freight.id,
            nothing,
            freight.pickup_ts,
            freight.delivery_ts,
            -1.0,
            0.0,
            false,
        ),
    )
    println("DISPATCH FAILURE: Freight ", freight.id, " could not be assigned")
end
