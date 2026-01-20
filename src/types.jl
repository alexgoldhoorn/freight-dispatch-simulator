# Data structure definitions for the freight dispatch simulator

"""
    Freight

Represents a freight delivery request with pickup and delivery locations and time windows.

# Fields
- `id::String`: Unique identifier for the freight
- `weight_kg::Float64`: Weight of the freight in kilograms
- `pickup_lat::Float64`: Latitude of pickup location
- `pickup_lon::Float64`: Longitude of pickup location
- `delivery_lat::Float64`: Latitude of delivery location
- `delivery_lon::Float64`: Longitude of delivery location
- `pickup_time::Dates.DateTime`: Pickup time window
- `delivery_time::Dates.DateTime`: Delivery time window
- `pickup_ts::Float64`: Pickup timestamp in simulation seconds
- `delivery_ts::Float64`: Delivery timestamp in simulation seconds
"""
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

"""
    VehicleState

Mutable state information for a vehicle during simulation.

# Fields
- `current_lat::Float64`: Current latitude position
- `current_lon::Float64`: Current longitude position
- `available_at::Dates.DateTime`: Time when vehicle becomes available
- `distance_travelled_km::Float64`: Total distance traveled
- `busy_time_s::Float64`: Total busy time in seconds
"""
mutable struct VehicleState
    current_lat::Float64
    current_lon::Float64
    available_at::Dates.DateTime
    distance_travelled_km::Float64
    busy_time_s::Float64
end

"""
    Vehicle

Represents a delivery vehicle with capacity, speed, and location information.

# Fields
- `id::String`: Unique identifier for the vehicle
- `start_lat::Float64`: Starting latitude position
- `start_lon::Float64`: Starting longitude position
- `base_lat::Union{Nothing,Float64}`: Base location latitude (optional)
- `base_lon::Union{Nothing,Float64}`: Base location longitude (optional)
- `capacity_kg::Float64`: Maximum cargo capacity in kilograms
- `speed_km_per_hour::Float64`: Travel speed in km/h
- `state::VehicleState`: Current state of the vehicle

# Constructors
- `Vehicle(id, start_lat, start_lon, capacity_kg, speed_km_per_hour)`: Base defaults to start location
- `Vehicle(id, start_lat, start_lon, base_lat, base_lon, capacity_kg, speed_km_per_hour)`: With explicit base
"""
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

"""
    VehicleInfo

Tracking structure used by dispatcher to monitor vehicle availability.

# Fields
- `id::String`: Vehicle identifier
- `capacity_kg::Float64`: Vehicle capacity
- `speed_km_per_hour::Float64`: Vehicle speed
- `available_at::Float64`: Simulation time when available
- `current_lat::Float64`: Current latitude
- `current_lon::Float64`: Current longitude
- `base_lat::Float64`: Base latitude
- `base_lon::Float64`: Base longitude
"""
mutable struct VehicleInfo
    id::String
    capacity_kg::Float64
    speed_km_per_hour::Float64
    available_at::Float64
    current_lat::Float64
    current_lon::Float64
    base_lat::Float64
    base_lon::Float64
end

"""
    FreightResult

Result record for a freight after simulation.

# Fields
- `freight_id::String`: Freight identifier
- `assigned_vehicle::Union{String,Nothing}`: Assigned vehicle ID (or nothing if failed)
- `pickup_time::Float64`: Actual pickup time
- `delivery_time::Float64`: Actual delivery time
- `completion_time::Float64`: Total completion time
- `distance_km::Float64`: Total distance traveled for this freight
- `success::Bool`: Whether freight was successfully delivered
"""
mutable struct FreightResult
    freight_id::String
    assigned_vehicle::Union{String,Nothing}
    pickup_time::Float64
    delivery_time::Float64
    completion_time::Float64
    distance_km::Float64
    success::Bool
end

"""
    VehicleAggregate

Aggregate statistics for a vehicle after simulation.

# Fields
- `vehicle_id::String`: Vehicle identifier
- `total_distance_km::Float64`: Total distance traveled
- `total_busy_time_s::Float64`: Total time spent on deliveries
- `total_freights_handled::Int64`: Number of freights handled
- `utilization_rate::Float64`: Vehicle utilization rate (0-1)
"""
mutable struct VehicleAggregate
    vehicle_id::String
    total_distance_km::Float64
    total_busy_time_s::Float64
    total_freights_handled::Int64
    utilization_rate::Float64
end

"""
    get_base_location(vehicle::Vehicle) -> Tuple{Float64, Float64}

Get the base location of a vehicle, defaulting to start location if not set.

# Returns
- Tuple of (base_lat, base_lon)
"""
function get_base_location(vehicle::Vehicle)
    base_lat = vehicle.base_lat !== nothing ? vehicle.base_lat : vehicle.start_lat
    base_lon = vehicle.base_lon !== nothing ? vehicle.base_lon : vehicle.start_lon
    return (base_lat, base_lon)
end
