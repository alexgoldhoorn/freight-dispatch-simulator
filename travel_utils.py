import math


def travel_time_s(dist_km, speed_kmh):
    """
    Calculate travel time in seconds given distance in kilometers and speed in km/h.
    
    Args:
        dist_km (float): Distance in kilometers
        speed_kmh (float): Speed in kilometers per hour
        
    Returns:
        float: Travel time in seconds
    """
    if speed_kmh <= 0:
        raise ValueError("Speed must be positive")
    
    # Time = Distance / Speed
    time_hours = dist_km / speed_kmh
    time_seconds = time_hours * 3600  # Convert hours to seconds
    return time_seconds


def haversine(lat1, lon1, lat2, lon2):
    """
    Calculate the great circle distance between two points on the earth (specified in decimal degrees).
    
    Args:
        lat1, lon1 (float): Latitude and longitude of first point
        lat2, lon2 (float): Latitude and longitude of second point
        
    Returns:
        float: Distance in kilometers
    """
    # Convert decimal degrees to radians
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])

    # Haversine formula
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    c = 2 * math.asin(math.sqrt(a))
    r = 6371  # Radius of earth in kilometers
    return c * r


def distance_and_time(lat1, lon1, lat2, lon2, speed_kmh):
    """
    Calculate both distance and travel time between two geographic points.
    
    Args:
        lat1, lon1 (float): Latitude and longitude of first point
        lat2, lon2 (float): Latitude and longitude of second point
        speed_kmh (float): Speed in kilometers per hour
        
    Returns:
        tuple: (distance_km, time_seconds)
    """
    dist_km = haversine(lat1, lon1, lat2, lon2)
    time_s = travel_time_s(dist_km, speed_kmh)
    return dist_km, time_s
