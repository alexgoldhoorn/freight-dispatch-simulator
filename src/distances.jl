# Distance calculation functions

"""
    haversine(lat1, lon1, lat2, lon2) -> Float64

Calculate the great-circle distance between two points on Earth using the Haversine formula.

# Arguments
- `lat1::Float64`: Latitude of first point in degrees
- `lon1::Float64`: Longitude of first point in degrees
- `lat2::Float64`: Latitude of second point in degrees
- `lon2::Float64`: Longitude of second point in degrees

# Returns
- Distance in kilometers

# Example
```julia
# Distance from New York to Los Angeles
distance = haversine(40.71, -74.01, 34.05, -118.24)
```
"""
function haversine(lat1, lon1, lat2, lon2)
    R = 6371  # Radius of Earth in kilometers
    lat1, lon1, lat2, lon2 = deg2rad.([lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = sin(dlat / 2)^2 + cos(lat1) * cos(lat2) * sin(dlon / 2)^2
    c = 2 * atan(sqrt(a), sqrt(1 - a))
    return R * c
end

"""
    sim_seconds(dt::Dates.DateTime, reference::Dates.DateTime) -> Float64

Convert a DateTime to simulation seconds relative to a reference time.

# Arguments
- `dt::Dates.DateTime`: The datetime to convert
- `reference::Dates.DateTime`: The reference (start) time

# Returns
- Time in seconds since reference
"""
function sim_seconds(dt::Dates.DateTime, reference::Dates.DateTime)
    return Dates.value(dt - reference) / 1000.0 # Convert milliseconds to seconds
end
