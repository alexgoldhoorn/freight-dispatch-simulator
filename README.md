# Freight Dispatch Simulator

A Julia package for simulating freight delivery systems with multiple dispatch strategies and interactive visualization capabilities.

## Features

- **Multiple Dispatch Strategies**: FCFS, Cost-based, Distance-based, and Overall Cost optimization
- **Interactive Visualization**: Generate HTML route maps with PlotlyJS
- **Comprehensive Testing**: Full test suite covering all dispatch strategies
- **Command Line Interface**: Easy-to-use CLI for running simulations
- **Flexible Data Input**: Support for CSV input files
- **Result Export**: Export simulation results and vehicle aggregates

## Installation

1. Clone the repository:
```bash
git clone https://github.com/alexgoldhoorn/freight-dispatch-simulator.git
cd freight-dispatch-simulator
```

2. Install dependencies:
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## Usage

### Command Line Interface

```bash
julia --project=. scripts/main.jl <input_directory> <strategy> <output_file> [options]
```

**Arguments:**
- `input_directory`: Directory containing `freights.csv` and `vehicles.csv`
- `strategy`: Dispatch strategy (`FCFS`, `Cost`, `Distance`, `OverallCost`)
- `output_file`: Output CSV file path for freight results

**Options:**
- `-m [map_file]`: Generate interactive route map (optional HTML file path)

**Examples:**
```bash
# Basic simulation
julia --project=. scripts/main.jl data/test0 FCFS results.csv

# With route map generation
julia --project=. scripts/main.jl data/test0 FCFS results.csv -m route_map.html

# Show help
julia --project=. scripts/main.jl --help
```

### Programmatic Usage

```julia
using FreightSimulator2
using CSV, DataFrames

# Load data
freights_df = CSV.read("data/test0/freights.csv", DataFrame)
vehicles_df = CSV.read("data/test0/vehicles.csv", DataFrame)

# Run simulation
freight_results, vehicle_aggregates = Simulation(
    freights_df, 
    vehicles_df, 
    3600.0,  # return to base buffer
    FCFSStrategy()
)

# Generate route map
generate_route_map(freight_results, vehicles_df, "route_map.html")
```

## Data Format

### Freights CSV
```csv
id,weight_kg,pickup_lat,pickup_lon,delivery_lat,delivery_lon,pickup_time,delivery_time
F1,100.0,40.71,-74.01,34.05,-118.24,0.0,10.0
F2,200.0,37.77,-122.42,41.87,-87.62,5.0,15.0
```

### Vehicles CSV
```csv
id,start_lat,start_lon,capacity_kg,speed_km_per_hour
V1,40.71,-74.01,500.0,60.0
V2,37.77,-122.42,1000.0,80.0
```

Optional columns for vehicles:
- `base_lat`, `base_lon`: Vehicle base location (defaults to start location)

## Dispatch Strategies

1. **FCFS (First Come, First Served)**: Processes freight in order of arrival
2. **Cost**: Assigns freight to the vehicle with lowest cost to pickup
3. **Distance**: Optimizes for shortest total distance (pickup + delivery + return)
4. **OverallCost**: Minimizes total time cost for the entire route

## Output

### Freight Results CSV
- `freight_id`: Freight identifier
- `assigned_vehicle`: Vehicle assigned to freight
- `pickup_time`: Pickup timestamp
- `delivery_time`: Delivery timestamp
- `completion_time`: Total completion time
- `distance_km`: Total distance traveled
- `success`: Whether freight was successfully assigned

### Vehicle Aggregates CSV
- `vehicle_id`: Vehicle identifier
- `total_distance_km`: Total distance traveled
- `total_busy_time_s`: Total time spent on deliveries
- `total_freights_handled`: Number of freights handled
- `utilization_rate`: Vehicle utilization rate

## Testing

Run the test suite:
```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

The tests cover:
- Basic simulation functionality
- All dispatch strategies
- CLI interface
- Data integrity and consistency

## Interactive Visualization

The package generates interactive HTML maps showing:
- Vehicle routes with different colors
- Pickup points (green circles)
- Delivery points (blue squares)
- Vehicle bases (purple diamonds)
- Failed freight (red X marks)
- Hover information for detailed data

## Dependencies

- `CSV.jl`: CSV file handling
- `DataFrames.jl`: Data manipulation
- `SimJulia.jl`: Discrete event simulation
- `Plots.jl`: Plotting infrastructure
- `PlotlyJS.jl`: Interactive visualization
- `Colors.jl`: Color handling
- `ResumableFunctions.jl`: Coroutine support

## Project Structure

```
freight-dispatch-simulator/
├── Project.toml                 # Package configuration
├── Manifest.toml               # Dependency lock file
├── README.md                   # This file
├── src/
│   ├── FreightSimulator2.jl    # Main module
│   └── MapVisualization.jl     # Route visualization
├── test/
│   └── runtests.jl            # Test suite
├── scripts/
│   └── main.jl                # CLI interface
└── data/
    ├── test0/                 # Basic test data
    ├── test1/                 # Additional test data
    └── test_failure/          # Failure scenario data
```

## Contributing

Code should follow Julia formatting conventions. Use:
```bash
julia --project=. -e 'using JuliaFormatter; format_file("filename.jl")'
```

## License

This project is licensed under the MIT License.
