module FreightSimulator2

using CSV
using DataFrames
using Dates
using JSON3
using SimJulia
using ResumableFunctions

export Freight,
    Vehicle,
    VehicleState,
    get_base_location,
    haversine,
    run_simulation,
    sim_seconds,
    Simulation,
    DispatchStrategy,
    FCFSStrategy,
    CostStrategy,
    DistanceStrategy,
    OverallCostStrategy,
    generate_route_map

# Define data structures
struct Freight
    id::String
    weight_kg::Float64
    pickup_lat::Float64
    pickup_lon::Float64
    delivery_lat::Float64
    delivery_lon::Float64
    pickup_time::Dates.DateTime
    delivery_time::Dates.DateTime
    pickup_ts::Float64
    delivery_ts::Float64
end

mutable struct VehicleState
    current_lat::Float64
    current_lon::Float64
    available_at::Dates.DateTime
    distance_travelled_km::Float64
    busy_time_s::Float64
end

struct Vehicle
    id::String
    start_lat::Float64
    start_lon::Float64
    base_lat::Union{Nothing,Float64}
    base_lon::Union{Nothing,Float64}
    capacity_kg::Float64
    speed_km_per_hour::Float64
    state::VehicleState

    function Vehicle(
        id::AbstractString,
        start_lat::Float64,
        start_lon::Float64,
        capacity_kg::Float64,
        speed_km_per_hour::Float64,
    )
        state = VehicleState(start_lat, start_lon, Dates.now(), 0.0, 0.0)
        return new(
            string(id),
            start_lat,
            start_lon,
            nothing,
            nothing,
            capacity_kg,
            speed_km_per_hour,
            state,
        )
    end

    function Vehicle(
        id::AbstractString,
        start_lat::Float64,
        start_lon::Float64,
        base_lat::Float64,
        base_lon::Float64,
        capacity_kg::Float64,
        speed_km_per_hour::Float64,
    )
        state = VehicleState(start_lat, start_lon, Dates.now(), 0.0, 0.0)
        return new(
            string(id),
            start_lat,
            start_lon,
            base_lat,
            base_lon,
            capacity_kg,
            speed_km_per_hour,
            state,
        )
    end
end

# Helper function to get base location (defaults to start location if base is not set)
function get_base_location(vehicle::Vehicle)
    base_lat = vehicle.base_lat !== nothing ? vehicle.base_lat : vehicle.start_lat
    base_lon = vehicle.base_lon !== nothing ? vehicle.base_lon : vehicle.start_lon
    return (base_lat, base_lon)
end

# Haversine distance function (in kilometers)
function haversine(lat1, lon1, lat2, lon2)
    R = 6371  # Radius of Earth in kilometers
    lat1, lon1, lat2, lon2 = deg2rad.([lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = sin(dlat/2)^2 + cos(lat1) * cos(lat2) * sin(dlon/2)^2
    c = 2 * atan(sqrt(a), sqrt(1-a))
    return R * c
end

# Helper function to convert DateTime to simulation seconds relative to reference
function sim_seconds(dt::Dates.DateTime, reference::Dates.DateTime)
    return Dates.value(dt - reference) / 1000.0 # Convert milliseconds to seconds
end

function run_simulation(freights::DataFrame, vehicles::DataFrame)
    sim = Simulation()
    println("Starting simulation...")

    # Convert numeric timestamps to DateTime (assuming they are seconds since Unix epoch)
    freights.pickup_time = Dates.unix2datetime.(freights.pickup_time)
    freights.delivery_time = Dates.unix2datetime.(freights.delivery_time)

    # Find the earliest timestamp to use as reference
    reference_time = minimum(vcat(freights.pickup_time, freights.delivery_time))

    # Convert all timestamps to simulation seconds relative to reference
    freights.pickup_sim_seconds = sim_seconds.(freights.pickup_time, reference_time)
    freights.delivery_sim_seconds = sim_seconds.(freights.delivery_time, reference_time)

    # Create Freight objects
    freight_objects = [
        Freight(
            string(freights[i, :id]),  # Convert to String type
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

    # Implement the simulation logic for each vehicle
    vehicle_inbox = Dict{String,Store{Freight}}()
    vehicles_info = Dict{String,VehicleInfo}()

    for i = 1:nrow(vehicles)
        vehicle_id = String(vehicles[i, :id])  # Convert to String type
        vehicle_inbox[vehicle_id] = Store{Freight}(sim)

        # Create vehicle info for dispatcher
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
            0.0,  # Initially available
            vehicles[i, :start_lat],
            vehicles[i, :start_lon],
            base_lat,
            base_lon,
        )

        @process run_vehicle(
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

    # Create a dispatcher process to put freight tasks in vehicle inboxes
    if length(freight_objects) > 0 && length(vehicle_inbox) > 0
        @process dispatch_freight(sim, freight_objects, vehicle_inbox, vehicles_info)
    end

    # Run simulation for a reasonable duration
    run(sim, 86400)  # Run for 24 hours

    return DataFrame() # Placeholder for the results
end

# Vehicle tracking structure for dispatcher
mutable struct VehicleInfo
    id::String
    capacity_kg::Float64
    speed_km_per_hour::Float64
    available_at::Float64  # Simulation time when vehicle becomes available
    current_lat::Float64
    current_lon::Float64
    base_lat::Float64
    base_lon::Float64
end

# FCFS Dispatcher process to assign freight to vehicles
@resumable function dispatch_freight(
    sim::Simulation,
    freight_objects::Vector{Freight},
    vehicle_inbox::Dict{String,Store{Freight}},
    vehicle_info::Dict{String,VehicleInfo},
)
    # Sort freights by pickup time (FCFS)
    sorted_freights = sort(freight_objects, by = f -> f.pickup_ts)

    println("Dispatcher: Starting FCFS dispatch for ", length(sorted_freights), " freights")

    for freight in sorted_freights
        # Wait until freight pickup time
        current_time = now(sim)
        if current_time < freight.pickup_ts
            wait_time = freight.pickup_ts - current_time
            println(
                "Dispatcher: Waiting ",
                wait_time,
                " seconds for freight ",
                freight.id,
                " pickup time",
            )
            @yield timeout(sim, wait_time)
        end

        current_time = now(sim)

        # Find the first available vehicle with sufficient capacity
        assigned_vehicle = nothing

        for (vehicle_id, inbox) in vehicle_inbox
            vehicle = vehicle_info[vehicle_id]

            # Check if vehicle has sufficient capacity and is available
            if vehicle.capacity_kg >= freight.weight_kg &&
               vehicle.available_at <= current_time
                assigned_vehicle = vehicle_id
                break
            end
        end

        if assigned_vehicle !== nothing
            println(
                "Dispatcher: Assigning freight ",
                freight.id,
                " (weight: ",
                freight.weight_kg,
                "kg) to vehicle ",
                assigned_vehicle,
            )

            # Calculate total travel time for this freight
            vehicle = vehicle_info[assigned_vehicle]

            # Distance from current vehicle location to pickup
            pickup_distance = haversine(
                vehicle.current_lat,
                vehicle.current_lon,
                freight.pickup_lat,
                freight.pickup_lon,
            )
            pickup_travel_time = pickup_distance / vehicle.speed_km_per_hour * 3600  # Convert to seconds

            # Distance from pickup to delivery
            delivery_distance = haversine(
                freight.pickup_lat,
                freight.pickup_lon,
                freight.delivery_lat,
                freight.delivery_lon,
            )
            delivery_travel_time = delivery_distance / vehicle.speed_km_per_hour * 3600  # Convert to seconds

            # Distance from delivery back to base
            return_distance = haversine(
                freight.delivery_lat,
                freight.delivery_lon,
                vehicle.base_lat,
                vehicle.base_lon,
            )
            return_travel_time = return_distance / vehicle.speed_km_per_hour * 3600  # Convert to seconds

            # Total travel time
            total_travel_time =
                pickup_travel_time + delivery_travel_time + return_travel_time

            # Update vehicle availability
            vehicle.available_at = current_time + total_travel_time
            vehicle.current_lat = vehicle.base_lat
            vehicle.current_lon = vehicle.base_lon

            # Send freight to vehicle's channel
            @yield put(vehicle_inbox[assigned_vehicle], freight)

            println(
                "Dispatcher: Vehicle ",
                assigned_vehicle,
                " will be available again at sim time ",
                vehicle.available_at,
            )
        else
            # Log failure for unassigned freight
            println(
                "DISPATCH FAILURE: Freight ",
                freight.id,
                " (weight: ",
                freight.weight_kg,
                "kg) could not be assigned to any vehicle at time ",
                current_time,
            )

            # Log details about why assignment failed
            println("  Available vehicles:")
            for (vehicle_id, vehicle) in vehicle_info
                println(
                    "    ",
                    vehicle_id,
                    ": capacity=",
                    vehicle.capacity_kg,
                    "kg, available_at=",
                    vehicle.available_at,
                    ", current_time=",
                    current_time,
                )
            end
        end
    end

    println("Dispatcher: All freights processed")
end

# VehicleProcess implementation
@resumable function run_vehicle(
    sim::Simulation,
    id::String,
    start_lat::Float64,
    start_lon::Float64,
    capacity_kg::Float64,
    speed_km_per_hour::Float64,
    inbox::Store{Freight},
    reference_time::Dates.DateTime,
)
    state = VehicleState(start_lat, start_lon, reference_time, 0.0, 0.0)
    base_lat, base_lon =
        get_base_location(Vehicle(id, start_lat, start_lon, capacity_kg, speed_km_per_hour))

    while true
        # Passivate until a freight task arrives
        freight = @yield get(inbox)

        # Drive to pickup location
        pickup_distance = haversine(
            state.current_lat,
            state.current_lon,
            freight.pickup_lat,
            freight.pickup_lon,
        )
        travel_time_to_pickup = pickup_distance / speed_km_per_hour * 3600  # Convert to seconds
        @yield timeout(sim, travel_time_to_pickup)

        # Update state
        state.current_lat, state.current_lon = freight.pickup_lat, freight.pickup_lon
        state.distance_travelled_km += pickup_distance
        state.busy_time_s += travel_time_to_pickup

        # Wait until freight pickup time if necessary
        current_sim_time = now(sim)
        if current_sim_time < freight.pickup_ts
            wait_time = freight.pickup_ts - current_sim_time
            @yield timeout(sim, wait_time)
        end

        # Drive to delivery location
        delivery_distance = haversine(
            state.current_lat,
            state.current_lon,
            freight.delivery_lat,
            freight.delivery_lon,
        )
        travel_time_to_delivery = delivery_distance / speed_km_per_hour * 3600  # Convert to seconds
        @yield timeout(sim, travel_time_to_delivery)

        # Update state
        state.current_lat, state.current_lon = freight.delivery_lat, freight.delivery_lon
        state.distance_travelled_km += delivery_distance
        state.busy_time_s += travel_time_to_delivery

        # Check if dispatcher queue is empty - for now, always return to base
        # In a full implementation, this would check a shared dispatcher queue
        return_to_base_distance =
            haversine(state.current_lat, state.current_lon, base_lat, base_lon)
        travel_time_to_base = return_to_base_distance / speed_km_per_hour * 3600  # Convert to seconds
        @yield timeout(sim, travel_time_to_base)

        # Update state - back at base
        state.current_lat, state.current_lon = base_lat, base_lon
        state.distance_travelled_km += return_to_base_distance
        state.busy_time_s += travel_time_to_base
    end
end

# Results collection structures
mutable struct FreightResult
    freight_id::String
    assigned_vehicle::Union{String,Nothing}
    pickup_time::Float64
    delivery_time::Float64
    completion_time::Float64
    distance_km::Float64
    success::Bool
end

mutable struct VehicleAggregate
    vehicle_id::String
    total_distance_km::Float64
    total_busy_time_s::Float64
    total_freights_handled::Int64
    utilization_rate::Float64
end

# Global result collectors
const FREIGHT_RESULTS = Vector{FreightResult}()
const VEHICLE_AGGREGATES = Dict{String,VehicleAggregate}()

# Dispatcher Strategies
abstract type DispatchStrategy end

struct FCFSStrategy <: DispatchStrategy end
struct CostStrategy <: DispatchStrategy end
struct DistanceStrategy <: DispatchStrategy end
struct OverallCostStrategy <: DispatchStrategy end

# Main Simulation function
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

function select_freights(strategy::FCFSStrategy, freight_objects::Vector{Freight})
    return sort(freight_objects; by = f -> f.pickup_ts)
end

function select_freights(strategy::CostStrategy, freight_objects::Vector{Freight})
    println("Selecting freights based on cost... (Placeholder)")
    return sort(freight_objects; by = f -> f.weight_kg) # Example placeholder
end

function select_freights(strategy::DistanceStrategy, freight_objects::Vector{Freight})
    println("Selecting freights based on distance... (Placeholder)")
    return sort(
        freight_objects;
        by = f -> haversine(f.pickup_lat, f.pickup_lon, f.delivery_lat, f.delivery_lon),
    )
end

function select_freights(strategy::OverallCostStrategy, freight_objects::Vector{Freight})
    println("Selecting freights based on overall cost... (Placeholder)")
    return freight_objects # Example placeholder
end

# FCFS Strategy: First available vehicle
function find_best_vehicle(
    strategy::FCFSStrategy,
    vehicle_info::Dict{String,VehicleInfo},
    vehicle_inbox::Dict{String,Store{Freight}},
    freight::Freight,
    current_time::Float64,
)
    for (vehicle_id, inbox) in vehicle_inbox
        vehicle = vehicle_info[vehicle_id]
        if vehicle.capacity_kg >= freight.weight_kg && vehicle.available_at <= current_time
            return vehicle_id
        end
    end
    return nothing
end

# Cost Strategy: Vehicle with lowest cost (closest to pickup)
function find_best_vehicle(
    strategy::CostStrategy,
    vehicle_info::Dict{String,VehicleInfo},
    vehicle_inbox::Dict{String,Store{Freight}},
    freight::Freight,
    current_time::Float64,
)
    best_vehicle = nothing
    best_cost = Inf

    for (vehicle_id, inbox) in vehicle_inbox
        vehicle = vehicle_info[vehicle_id]
        if vehicle.capacity_kg >= freight.weight_kg && vehicle.available_at <= current_time
            # Calculate cost as distance to pickup location
            cost = haversine(
                vehicle.current_lat,
                vehicle.current_lon,
                freight.pickup_lat,
                freight.pickup_lon,
            )
            if cost < best_cost
                best_cost = cost
                best_vehicle = vehicle_id
            end
        end
    end

    return best_vehicle
end

# Distance Strategy: Vehicle with shortest total distance
function find_best_vehicle(
    strategy::DistanceStrategy,
    vehicle_info::Dict{String,VehicleInfo},
    vehicle_inbox::Dict{String,Store{Freight}},
    freight::Freight,
    current_time::Float64,
)
    best_vehicle = nothing
    best_distance = Inf

    for (vehicle_id, inbox) in vehicle_inbox
        vehicle = vehicle_info[vehicle_id]
        if vehicle.capacity_kg >= freight.weight_kg && vehicle.available_at <= current_time
            # Calculate total distance: pickup + delivery + return to base
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
            total_distance = pickup_distance + delivery_distance + return_distance

            if total_distance < best_distance
                best_distance = total_distance
                best_vehicle = vehicle_id
            end
        end
    end

    return best_vehicle
end

# Overall Cost Strategy: Vehicle with lowest time cost
function find_best_vehicle(
    strategy::OverallCostStrategy,
    vehicle_info::Dict{String,VehicleInfo},
    vehicle_inbox::Dict{String,Store{Freight}},
    freight::Freight,
    current_time::Float64,
)
    best_vehicle = nothing
    best_time_cost = Inf

    for (vehicle_id, inbox) in vehicle_inbox
        vehicle = vehicle_info[vehicle_id]
        if vehicle.capacity_kg >= freight.weight_kg && vehicle.available_at <= current_time
            # Calculate time cost: total travel time
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

            pickup_time = pickup_distance / vehicle.speed_km_per_hour * 3600
            delivery_time = delivery_distance / vehicle.speed_km_per_hour * 3600
            return_time = return_distance / vehicle.speed_km_per_hour * 3600
            total_time = pickup_time + delivery_time + return_time

            if total_time < best_time_cost
                best_time_cost = total_time
                best_vehicle = vehicle_id
            end
        end
    end

    return best_vehicle
end

function process_assignment(
    vehicle_info::Dict{String,VehicleInfo},
    assigned_vehicle::String,
    freight::Freight,
    current_time::Float64,
)
    println("Dispatcher: Assigning freight ", freight.id, " to vehicle ", assigned_vehicle)
    vehicle = vehicle_info[assigned_vehicle]
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
    pickup_travel_time = pickup_distance / vehicle.speed_km_per_hour * 3600
    delivery_travel_time = delivery_distance / vehicle.speed_km_per_hour * 3600
    return_travel_time = return_distance / vehicle.speed_km_per_hour * 3600
    total_travel_time = pickup_travel_time + delivery_travel_time + return_travel_time
    completion_time = current_time + total_travel_time
    vehicle.available_at = completion_time
    vehicle.current_lat = vehicle.base_lat
    vehicle.current_lon = vehicle.base_lon
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
    return nothing
end

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

# Enhanced vehicle process with result tracking
@resumable function run_vehicle_with_results(
    sim::SimJulia.Simulation,
    id::AbstractString,
    start_lat::Float64,
    start_lon::Float64,
    capacity_kg::Float64,
    speed_km_per_hour::Float64,
    inbox::Store{Freight},
    reference_time::Dates.DateTime,
)
    id_str = string(id)
    state = VehicleState(start_lat, start_lon, reference_time, 0.0, 0.0)
    base_lat, base_lon = get_base_location(
        Vehicle(id_str, start_lat, start_lon, capacity_kg, speed_km_per_hour),
    )

    while true
        # Wait for freight assignment
        freight = @yield get(inbox)

        # Drive to pickup location
        pickup_distance = haversine(
            state.current_lat,
            state.current_lon,
            freight.pickup_lat,
            freight.pickup_lon,
        )
        travel_time_to_pickup = pickup_distance / speed_km_per_hour * 3600
        @yield timeout(sim, travel_time_to_pickup)

        # Update state
        state.current_lat, state.current_lon = freight.pickup_lat, freight.pickup_lon
        state.distance_travelled_km += pickup_distance
        state.busy_time_s += travel_time_to_pickup

        # Wait until freight pickup time if necessary
        current_sim_time = now(sim)
        if current_sim_time < freight.pickup_ts
            wait_time = freight.pickup_ts - current_sim_time
            @yield timeout(sim, wait_time)
        end

        # Drive to delivery location
        delivery_distance = haversine(
            state.current_lat,
            state.current_lon,
            freight.delivery_lat,
            freight.delivery_lon,
        )
        travel_time_to_delivery = delivery_distance / speed_km_per_hour * 3600
        @yield timeout(sim, travel_time_to_delivery)

        # Update state
        state.current_lat, state.current_lon = freight.delivery_lat, freight.delivery_lon
        state.distance_travelled_km += delivery_distance
        state.busy_time_s += travel_time_to_delivery

        # Return to base
        return_to_base_distance =
            haversine(state.current_lat, state.current_lon, base_lat, base_lon)
        travel_time_to_base = return_to_base_distance / speed_km_per_hour * 3600
        @yield timeout(sim, travel_time_to_base)

        # Update state - back at base
        state.current_lat, state.current_lon = base_lat, base_lon
        state.distance_travelled_km += return_to_base_distance
        state.busy_time_s += travel_time_to_base

        # Update vehicle aggregates
        agg = VEHICLE_AGGREGATES[id_str]
        agg.total_distance_km = state.distance_travelled_km
        agg.total_busy_time_s = state.busy_time_s
        agg.total_freights_handled += 1
    end
end

# Include MapVisualization module
include("MapVisualization.jl")

end # module
