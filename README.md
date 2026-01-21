# Freight Dispatch Simulator

A Julia package for simulating freight delivery systems with multiple dispatch strategies and interactive visualization capabilities.

## Important: Greedy Heuristics

The current dispatch strategies are **greedy heuristics** that make locally optimal decisions without backtracking. They do NOT guarantee globally optimal solutions. Each strategy processes freights sequentially and assigns to the "best" currently available vehicle without lookahead or reassignment. For provably optimal solutions, see [Future Work](#future-work).

## Features

- **Four Greedy Dispatch Strategies**: FCFS, Cost-based, Distance-based, and Overall Cost
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
using FreightDispatchSimulator
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

## Examples and Visualizations

Check out `examples.ipynb` for comprehensive examples with visualizations:
- Comparison of all four dispatch strategies
- Performance metrics (distance, utilization, success rates, completion times)
- Interactive charts and graphs using Plots.jl
- Route map generation examples
- Strategy performance dashboard

To run the notebook (recommended method to avoid long setup times):
```bash
# Start Jupyter with the project environment already activated
julia --project=. -e 'using IJulia; notebook(dir=pwd())'
```

Or if you prefer the traditional way:
```bash
jupyter notebook examples.ipynb
# Note: First cell will activate environment (may take longer on first run)
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

All strategies are **greedy heuristics** implemented in `src/strategies.jl`:

| Strategy | Greedy Criterion | Best Use Case |
|----------|------------------|---------------|
| **FCFS** | First available vehicle | Simple, predictable allocation |
| **Cost** | Closest vehicle to pickup | Minimize empty miles |
| **Distance** | Shortest total route distance | Minimize fuel consumption |
| **OverallCost** | Fastest route completion (accounts for speed) | Time-sensitive deliveries |

### Usage Examples

```julia
using FreightDispatchSimulator
using CSV, DataFrames

freights_df = CSV.read("data/urban/freights.csv", DataFrame)
vehicles_df = CSV.read("data/urban/vehicles.csv", DataFrame)

# Run with different strategies
freight_results, vehicle_agg = Simulation(freights_df, vehicles_df, 3600.0, FCFSStrategy())
freight_results, vehicle_agg = Simulation(freights_df, vehicles_df, 3600.0, DistanceStrategy())
```

See `examples.ipynb` for detailed comparisons with realistic datasets (urban, long-haul, mixed scenarios).

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

The package follows Julia best practices with a modular architecture:

```
freight-dispatch-simulator/
├── Project.toml                      # Package configuration
├── Manifest.toml                     # Dependency lock file
├── README.md                         # This file
├── examples.ipynb                    # Jupyter notebook with examples
├── src/
│   ├── FreightDispatchSimulator.jl  # Main module (exports all functionality)
│   ├── types.jl                      # Data structure definitions
│   ├── distances.jl                  # Distance calculations (Haversine)
│   ├── strategies.jl                 # Dispatch strategy implementations
│   ├── dispatcher.jl                 # Dispatcher logic
│   ├── vehicle.jl                    # Vehicle process
│   ├── simulation.jl                 # Main simulation orchestration
│   └── MapVisualization.jl           # Route visualization
├── test/
│   └── runtests.jl                  # Test suite
├── scripts/
│   └── main.jl                      # CLI interface
└── data/
    ├── urban/                       # US: NYC urban deliveries (15 freights, 5 vehicles)
    ├── longhaul/                    # US: Cross-country routes (8 freights, 3 vehicles)
    ├── mixed/                       # US: Combined urban & long-haul (20 freights, 6 vehicles)
    ├── eu_urban/                    # EU: Netherlands cities (12 freights, 4 vehicles)
    ├── eu_longhaul/                 # EU: Cross-Europe routes (10 freights, 4 vehicles)
    ├── iberia/                      # Iberia: Spain & Portugal (15 freights, 5 vehicles)
    ├── benelux/                     # Benelux: NL/BE/LU region (12 freights, 4 vehicles)
    ├── test0/                       # Basic test data
    ├── test1/                       # Additional test data
    └── test_failure/                # Failure scenario data
```

### Architecture

The codebase is organized into logical modules:
- **types.jl**: Core data structures (Freight, Vehicle, VehicleState, etc.)
- **distances.jl**: Geographic distance calculations
- **strategies.jl**: Dispatch strategy definitions and vehicle selection logic
- **dispatcher.jl**: Main dispatching process that assigns freights to vehicles
- **vehicle.jl**: Vehicle simulation process
- **simulation.jl**: Top-level simulation orchestration
- **MapVisualization.jl**: Interactive route map generation

## Contributing

Code should follow Julia formatting conventions. Use:
```bash
julia --project=. -e 'using JuliaFormatter; format_file("filename.jl")'
```

## Future Work

The current implementation uses greedy heuristics that provide fast, reasonable solutions but do not guarantee optimality. Future enhancements could include:

### True Optimization Approaches

**Mixed Integer Linear Programming (MILP)**
- Formulate as Vehicle Routing Problem with Time Windows (VRPTW)
- Use optimization solvers (HiGHS.jl, Gurobi, CPLEX via JuMP.jl)
- Provide provably optimal solutions (within time limits)
- Better for batch/offline planning scenarios

**Challenges with MILP Integration**:
- Current simulation is event-driven and dynamic (freights arrive over time)
- MILP works best for static problems (all freights known upfront)
- Would require different architecture (batch assignment or rolling horizon)
- Computational cost scales with problem size

**Example MILP Formulation** (simplified):
```julia
using JuMP, HiGHS

model = Model(HiGHS.Optimizer)
@variable(model, x[1:n_freights, 1:n_vehicles], Bin)  # Assignment variables
@constraint(model, [i=1:n_freights], sum(x[i,:]) == 1)  # Each freight assigned once
@objective(model, Min, sum(distance[i,j] * x[i,j] for i=1:n_freights, j=1:n_vehicles))
optimize!(model)
```

### Other Potential Enhancements

- **Metaheuristics**: Simulated annealing, genetic algorithms, ant colony optimization
- **Machine Learning**: Learn dispatch policies from historical data
- **Multi-objective Optimization**: Balance multiple criteria (distance, time, cost, emissions)
- **Dynamic Reassignment**: Allow in-flight route adjustments
- **Stochastic Models**: Account for uncertainty in travel times and freight arrivals

### Contributing

Contributions implementing these enhancements are welcome! Please open an issue to discuss major changes.

## License

This project is licensed under the MIT License.
