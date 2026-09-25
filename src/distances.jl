# Distance and travel-time helpers

const EARTH_RADIUS_KM = 6371.0

"""
    haversine(lat1, lon1, lat2, lon2) -> Float64

Great-circle distance in kilometres between two points given in degrees.

```julia
haversine(40.71, -74.01, 34.05, -118.24)  # New York -> Los Angeles ≈ 3936 km
```
"""
function haversine(lat1::Real, lon1::Real, lat2::Real, lon2::Real)
    φ1, φ2 = deg2rad(lat1), deg2rad(lat2)
    Δφ = φ2 - φ1
    Δλ = deg2rad(lon2 - lon1)
    a = sin(Δφ / 2)^2 + cos(φ1) * cos(φ2) * sin(Δλ / 2)^2
    return 2 * EARTH_RADIUS_KM * atan(sqrt(a), sqrt(1 - a))
end

"""
    travel_time_s(distance_km, speed_km_per_hour) -> Float64

Travel time in seconds for a distance at constant speed.
"""
travel_time_s(distance_km::Real, speed_km_per_hour::Real) =
    distance_km / speed_km_per_hour * 3600.0

"""
    sim_seconds(dt::DateTime, reference::DateTime) -> Float64

Seconds elapsed between `reference` and `dt`.
"""
sim_seconds(dt::Dates.DateTime, reference::Dates.DateTime) =
    Dates.value(dt - reference) / 1000.0
