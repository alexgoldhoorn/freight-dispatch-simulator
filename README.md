# DispatchSimulation.jl

[![Build Status](https://github.com/username/DispatchSimulation.jl/workflows/CI/badge.svg)](https://github.com/username/DispatchSimulation.jl/actions)
[![Coverage](https://codecov.io/gh/username/DispatchSimulation.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/username/DispatchSimulation.jl)
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://username.github.io/DispatchSimulation.jl/stable)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## 1. Project Overview & Purpose

DispatchSimulation.jl is a Julia package designed to simulate freight dispatch operations using various optimization strategies. This framework models freight distribution systems to evaluate dispatch strategies like First-Come-First-Served (FCFS), Cost-based, Distance-based, and Overall Cost optimization, ultimately improving operational efficiency.

### Key Features
- Multiple dispatch strategies for freight optimization
- Support for various vehicle types and constraints
- CSV-based input/output for integration with existing systems
- Comprehensive simulation analytics and reporting
- Configurable parameters for different operational scenarios

### Use Cases
- Logistics optimization analysis
- Fleet management strategy evaluation
- Academic research in operations research
- Supply chain efficiency assessment

## 2. Installation

### Package Manager Installation

```julia
using Pkg
Pkg.add("DispatchSimulation")
```

### Development Installation

To install the development version:
```julia
using Pkg
Pkg.add(url="https://github.com/username/DispatchSimulation.jl")
```

For local development:
```julia
using Pkg
Pkg.develop(path="/path/to/DispatchSimulation.jl")
```

## 3. Quick Start / CLI Usage

### Basic Usage

To use this package programmatically:
```julia
using DispatchSimulation

result = simulate_dispatch(
    freights_file="freights.csv",
    vehicles_file="vehicles.csv",
    strategy=:fcfs
)
```

### Command Line Interface

Run a simulation via command line:
```shell
julia scripts/main.jl data/test0 FCFS results.csv
```

Or run with a specific strategy:
```shell
julia scripts/main.jl data/test0 Cost results.csv
```

Available strategies:
- `FCFS` - First-Come-First-Served
- `Cost` - Cost-based optimization
- `Distance` - Distance-based optimization
- `OverallCost` - Overall cost optimization

## 4. Dispatch Strategy Details

### First-Come-First-Served (FCFS)
- **Strategy**: `FCFS`
- **Description**: Assigns freights to vehicles in order of arrival
- **Advantages**: Simple, fair, low computational overhead
- **Use Cases**: High-volume operations where simplicity is prioritized

### Cost-Based Dispatch
- **Strategy**: `Cost`
- **Description**: Minimizes operational cost by selecting the nearest vehicle to pickup location
- **Optimization**: Considers distance to pickup location as cost metric
- **Use Cases**: Cost-sensitive operations with variable pricing

### Distance-Based Dispatch
- **Strategy**: `Distance`
- **Description**: Minimizes total travel distance (pickup + delivery + return to base)
- **Optimization**: Assigns vehicle with shortest total distance for each freight
- **Use Cases**: Time-sensitive deliveries, urban distribution

### Overall Cost Optimization
- **Strategy**: `OverallCost`
- **Description**: Minimizes total travel time as a proxy for operational cost
- **Optimization**: Considers total time including pickup, delivery, and return
- **Use Cases**: Complex operations requiring optimal resource allocation

## 5. Input Data Formats

### `freights.csv` Format

| Column         | Type     | Description                    |
|----------------|----------|--------------------------------|
| `id`           | `String` | Unique freight identifier      |
| `weight_kg`    | `Float64`| Weight in kilograms            |
| `pickup_lat`   | `Float64`| Latitude of pickup location    |
| `pickup_lon`   | `Float64`| Longitude of pickup location   |
| `delivery_lat` | `Float64`| Latitude of delivery location  |
| `delivery_lon` | `Float64`| Longitude of delivery location |
| `pickup_time`  | `Float64`| Pickup time in simulation time |
| `delivery_time`| `Float64`| Delivery time in simulation time|

### `vehicles.csv` Format

| Column            | Type     | Description                              |
|-------------------|----------|------------------------------------------|
| `id`              | `String` | Unique vehicle identifier                |
| `start_lat`       | `Float64`| Starting latitude                        |
| `start_lon`       | `Float64`| Starting longitude                       |
| `capacity_kg`     | `Float64`| Vehicle's weight capacity in kg          |
| `speed_km_per_hour`| `Float64`| Vehicle speed in km/h                    |

## 6. Output Description

After running the simulation, results are generated in CSV format including:

### Freight Results
The main output file contains detailed information for each freight:

```julia
struct FreightResult
    freight_id::String
    assigned_vehicle::Union{String, Nothing}
    pickup_time::Float64
    delivery_time::Float64
    completion_time::Float64
    distance_km::Float64
    success::Bool
end
```

### Vehicle Aggregates
A separate file (`*_vehicles.csv`) contains summary statistics for each vehicle:

```julia
struct VehicleAggregate
    vehicle_id::String
    total_distance_km::Float64
    total_busy_time_s::Float64
    total_freights_handled::Int64
    utilization_rate::Float64
end
```

## 7. Example Scenarios

### Minimum Working Example

```julia
using DispatchSimulation

# Create sample data
freights = [(
    id="F1", 
    weight_kg=100.0, 
    pickup_lat=40.71, 
    pickup_lon=-74.01, 
    delivery_lat=34.05, 
    delivery_lon=-118.24, 
    pickup_time=0.0, 
    delivery_time=10.0
)]

vehicles = [(
    id="V1", 
    start_lat=40.71, 
    start_lon=-74.01, 
    capacity_kg=1000.0, 
    speed_km_per_hour=60.0
)]

result = simulate_dispatch(freights, vehicles, strategy=:fcfs)
```

### Comparing Different Strategies

```julia
using DispatchSimulation

strategies = ["FCFS", "Cost", "Distance", "OverallCost"]
results = Dict{String, Tuple{DataFrame, DataFrame}}()

for strategy in strategies
    freight_results, vehicle_results = Simulation(
        freights_df, 
        vehicles_df, 
        3600.0, 
        get_strategy(strategy)
    )
    results[strategy] = (freight_results, vehicle_results)
end

# Compare performance
for (strategy, (freight_df, vehicle_df)) in results
    success_rate = sum(freight_df.success) / nrow(freight_df)
    total_distance = sum(vehicle_df.total_distance_km)
    println("$strategy: Success rate = $success_rate, Total distance = $total_distance km")
end
```

### Large-Scale Scenario

```julia
using DispatchSimulation, CSV, DataFrames

# Load large dataset
freights_df = CSV.read("data/large_freights.csv", DataFrame)
vehicles_df = CSV.read("data/large_vehicles.csv", DataFrame)

# Run simulation with different strategies
for strategy in ["FCFS", "Cost", "Distance", "OverallCost"]
    println("Running simulation with $strategy strategy...")
    
    freight_results, vehicle_results = Simulation(
        freights_df, 
        vehicles_df, 
        3600.0, 
        get_strategy(strategy)
    )
    
    # Save results
    CSV.write("results_$(lowercase(strategy)).csv", freight_results)
    CSV.write("results_$(lowercase(strategy))_vehicles.csv", vehicle_results)
end
```

## 8. Simulation Parameter Reference

### Command Line Arguments

| Argument | Position | Description |
|----------|----------|-------------|
| `input_directory` | 1 | Directory containing `freights.csv` and `vehicles.csv` |
| `dispatcher_type` | 2 | Strategy: `FCFS`, `Cost`, `Distance`, or `OverallCost` |
| `output_file` | 3 | Output CSV file path for freight results |

### Julia Function Parameters

#### `Simulation` Function

```julia
function Simulation(
    freights::DataFrame,
    vehicles::DataFrame,
    return_to_base_buffer::Float64 = 3600.0,
    strategy::DispatchStrategy = FCFSStrategy()
)
```

Parameters:
- `freights`: DataFrame containing freight information
- `vehicles`: DataFrame containing vehicle information  
- `return_to_base_buffer`: Additional simulation time (seconds) for vehicles to return to base
- `strategy`: Dispatch strategy instance

#### Strategy Selection

```julia
function get_strategy(strategy_name::String)
    if strategy_name == "FCFS"
        return FCFSStrategy()
    elseif strategy_name == "Cost"
        return CostStrategy()
    elseif strategy_name == "Distance"
        return DistanceStrategy()
    elseif strategy_name == "OverallCost"
        return OverallCostStrategy()
    else
        error("Unknown strategy: " * strategy_name)
    end
end
```

### Performance Considerations

- **Simulation Time**: Automatically calculated based on maximum delivery time plus buffer
- **Distance Calculation**: Uses Haversine formula for geographic distance
- **Vehicle Routing**: Vehicles return to base after each delivery
- **Capacity Constraints**: Enforced based on freight weight vs vehicle capacity

---

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Citation

If you use this package in your research, please cite:

```bibtex
@software{dispatchsimulation_jl,
  title = {DispatchSimulation.jl: A Julia Package for Freight Dispatch Optimization},
  author = {Your Name},
  year = {2024},
  url = {https://github.com/username/DispatchSimulation.jl}
}
```

## References

- [SimJulia Documentation](https://github.com/BenLauwens/SimJulia.jl) - Discrete event simulation framework
- [DataFrames Documentation](https://dataframes.juliadata.org/stable/) - Data manipulation and analysis
