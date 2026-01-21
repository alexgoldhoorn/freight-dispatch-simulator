# Freight Dispatch Simulator

A Julia package for simulating freight delivery systems with multiple dispatch strategies and interactive visualization capabilities.

## Important: Greedy Heuristics vs MILP Optimization

**Main Branch:** Implements **greedy heuristics** that make locally optimal decisions without backtracking. They do NOT guarantee globally optimal solutions. Each strategy processes freights sequentially and assigns to the "best" currently available vehicle without lookahead or reassignment.

**MILP Branch (`feature/milp-optimization`):** Implements exact **Mixed Integer Linear Programming** optimization using JuMP.jl and HiGHS solver. Finds provably optimal solutions but with higher computational cost. See [MILP Optimization](#milp-optimization-branch) below.

## Features

- **Four Greedy Dispatch Strategies**: FCFS, Cost-based, Distance-based, and Overall Cost
- **MILP Exact Optimization** *(feature branch)*: Provably optimal solutions using JuMP + HiGHS
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

To run the notebook:
```bash
jupyter notebook examples.ipynb
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

## MILP Optimization (Branch)

The `feature/milp-optimization` branch implements **exact optimization** using Mixed Integer Linear Programming as an alternative to greedy heuristics.

### Key Features

- **Provably Optimal Solutions**: Uses JuMP.jl with HiGHS solver
- **Comparison Notebook**: `examples_milp_comparison.ipynb` compares greedy vs MILP with:
  - Optimality gaps (how much better MILP performs)
  - Solving time comparisons
  - Scalability analysis across datasets

### Usage

```julia
using FreightDispatchSimulator
using CSV, DataFrames

freights = CSV.read("data/urban/freights.csv", DataFrame)
vehicles = CSV.read("data/urban/vehicles.csv", DataFrame)

# MILP optimization
result = optimize_dispatch(freights, vehicles, time_limit=60.0)

println("Optimal distance: ", result.objective_value, " km")
println("Solve time: ", result.solve_time, " seconds")
println("Status: ", result.termination_status)
```

### Typical Results

From testing on demo datasets:

| Dataset | Freights | Greedy (Distance) | MILP Optimal | Gap | Time Comparison |
|---------|----------|-------------------|--------------|-----|-----------------|
| test0 | 2 | 13842 km | 13842 km | 0% | Greedy: 0.002s, MILP: 0.07s |
| Urban | 15 | 266 km | 266 km | 0-2% | Greedy: 0.2s, MILP: 0.07s |
| EU Urban | 12 | ~250 km | ~240 km | 2-5% | Greedy: 0.1s, MILP: 0.05s |

**Key Insights:**
- **Optimality Gap**: Greedy Distance strategy typically within 0-5% of optimal
- **Speed Tradeoff**: MILP can be faster for small problems (no simulation overhead), but scales poorly
- **Scalability**: MILP struggles with >20 freights, greedy scales linearly

### When to Use MILP

**Use MILP when:**
- Batch planning with all freights known upfront
- Small-medium problems (<20 freights)
- Optimality worth the computational cost
- Offline/strategic planning scenarios

**Use Greedy when:**
- Real-time/online decisions
- Large-scale problems (50+ freights)
- Sub-second response time required
- Good-enough solutions acceptable

### Checkout the MILP Branch

```bash
git checkout feature/milp-optimization
julia --project=. -e 'using Pkg; Pkg.instantiate()'
jupyter notebook examples_milp_comparison.ipynb
```

## Future Work

The main branch uses greedy heuristics (fast, good-enough solutions) and the MILP branch implements exact optimization (slow, optimal solutions). Future enhancements could include:

### Advanced Optimization

- **Metaheuristics**: Simulated annealing, genetic algorithms, ant colony optimization
- **Machine Learning**: Learn dispatch policies from historical data
- **Multi-objective Optimization**: Balance multiple criteria (distance, time, cost, emissions)
- **Dynamic Reassignment**: Allow in-flight route adjustments
- **Stochastic Models**: Account for uncertainty in travel times and freight arrivals

### Contributing

Contributions implementing these enhancements are welcome! Please open an issue to discuss major changes.

## License

This project is licensed under the MIT License.
