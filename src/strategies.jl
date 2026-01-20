# Dispatch strategy definitions and implementations

"""
    DispatchStrategy

Abstract base type for all dispatch strategies. Each strategy determines how freights
are assigned to vehicles based on different optimization criteria.
"""
abstract type DispatchStrategy end

"""
    FCFSStrategy <: DispatchStrategy

First Come, First Served strategy - assigns freights to the first available vehicle
with sufficient capacity. Simple and fair but may not optimize for distance or time.
"""
struct FCFSStrategy <: DispatchStrategy end

"""
    CostStrategy <: DispatchStrategy

Cost-based strategy - assigns freight to the vehicle with the lowest cost to reach
the pickup location (closest vehicle). Minimizes empty miles but doesn't consider
delivery distance or return-to-base cost.
"""
struct CostStrategy <: DispatchStrategy end

"""
    DistanceStrategy <: DispatchStrategy

Distance-based strategy - minimizes total distance for the complete route
(pickup + delivery + return to base). Best for reducing total mileage and fuel costs.
"""
struct DistanceStrategy <: DispatchStrategy end

"""
    OverallCostStrategy <: DispatchStrategy

Overall cost strategy - minimizes total time cost for the entire route, accounting
for vehicle speed. Best for time-sensitive deliveries and maximizing throughput.
"""
struct OverallCostStrategy <: DispatchStrategy end

# Strategy-specific freight selection

"""
    select_freights(strategy::DispatchStrategy, freight_objects::Vector{Freight}) -> Vector{Freight}

Sort freights to determine processing order. For greedy heuristics, all strategies
process freights in pickup time order. The optimization happens in vehicle selection
(find_best_vehicle), not in freight ordering.

Note: True optimization would require batch assignment (e.g., MILP) rather than
greedy sequential processing.
"""
function select_freights(strategy::FCFSStrategy, freight_objects::Vector{Freight})
    return sort(freight_objects; by = f -> f.pickup_ts)
end

function select_freights(strategy::CostStrategy, freight_objects::Vector{Freight})
    # Greedy heuristic: process in pickup time order, optimize vehicle selection
    return sort(freight_objects; by = f -> f.pickup_ts)
end

function select_freights(strategy::DistanceStrategy, freight_objects::Vector{Freight})
    # Greedy heuristic: process in pickup time order, optimize vehicle selection
    return sort(freight_objects; by = f -> f.pickup_ts)
end

function select_freights(strategy::OverallCostStrategy, freight_objects::Vector{Freight})
    # Greedy heuristic: process in pickup time order, optimize vehicle selection
    return sort(freight_objects; by = f -> f.pickup_ts)
end

# Strategy-specific vehicle selection

"""
    find_best_vehicle(strategy::DispatchStrategy, vehicle_info, vehicle_inbox, freight, current_time)

Find the best vehicle for a freight based on the dispatch strategy.

# Returns
- Vehicle ID string if a suitable vehicle is found, `nothing` otherwise
"""
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
