# Vehicle process logic for executing freight deliveries

"""
    run_vehicle_with_results(sim, id, start_lat, start_lon, capacity_kg, speed_km_per_hour, inbox, reference_time)

Vehicle process that executes freight deliveries assigned by the dispatcher.
Runs as a SimJulia resumable function (coroutine) during the simulation.

# Arguments
- `sim::SimJulia.Simulation`: The simulation environment
- `id::AbstractString`: Vehicle identifier
- `start_lat::Float64`: Starting latitude
- `start_lon::Float64`: Starting longitude
- `capacity_kg::Float64`: Vehicle capacity in kilograms
- `speed_km_per_hour::Float64`: Travel speed in km/h
- `inbox::Store{Freight}`: Channel for receiving freight assignments
- `reference_time::Dates.DateTime`: Reference time for the simulation

# Process Flow
1. Wait for freight assignment from dispatcher
2. Travel to pickup location
3. Wait until freight pickup time if necessary
4. Travel to delivery location
5. Return to base
6. Update vehicle aggregates
7. Repeat
"""
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

        # Update vehicle aggregates (redundant with dispatcher update, but kept for consistency)
        # The dispatcher already updates these values, but this ensures accuracy
        # if the simulation model changes in the future
        agg = VEHICLE_AGGREGATES[id_str]
        agg.total_distance_km = state.distance_travelled_km
        agg.total_busy_time_s = state.busy_time_s
        # Note: total_freights_handled is incremented by dispatcher
    end
end
