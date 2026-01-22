# Freight Dispatch Simulator

A Julia package for simulating freight delivery systems with both greedy heuristics and exact optimization, featuring interactive visualization capabilities.

## Features

- **Three Solution Approaches**:
  - **Greedy Heuristics**: Fast algorithms (FCFS, Cost, Distance, OverallCost) for real-time decisions (milliseconds)
  - **Local Search**: Metaheuristic that improves greedy solutions through iterative refinement (seconds)
  - **MILP Optimization**: Exact optimization using Mixed Integer Linear Programming for provably optimal solutions (minutes)
- **Interactive Visualization**: Generate HTML route maps with PlotlyJS
- **Comprehensive Comparison**: Compare all approaches with performance metrics
- **Command Line Interface**: Easy-to-use CLI for running simulations
- **Flexible Data Input**: Support for CSV input files
- **Multiple Datasets**: US and EU scenarios (urban, long-haul, mixed)
- **Theoretical Documentation**: Detailed explanation of algorithms in `SOLUTION_APPROACHES.md`

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

## Quick Start

### Greedy Heuristic

```julia
using FreightDispatchSimulator
using CSV, DataFrames

# Load data
freights_df = CSV.read("data/test0/freights.csv", DataFrame)
vehicles_df = CSV.read("data/test0/vehicles.csv", DataFrame)

# Run simulation with greedy strategy
freight_results, vehicle_aggregates = Simulation(
    freights_df,
    vehicles_df,
    3600.0,  # return to base buffer
    DistanceStrategy()
)

# Generate route map
generate_route_map(freight_results, vehicles_df, "route_map.html")
```

### Local Search (Metaheuristic)

```julia
using FreightDispatchSimulator
using CSV, DataFrames

# Load data
freights = CSV.read("data/urban/freights.csv", DataFrame)
vehicles = CSV.read("data/urban/vehicles.csv", DataFrame)

# Start with greedy solution
greedy_result = Simulation(freights, vehicles, 3600.0, DistanceStrategy())

# Improve with local search
improved = local_search_optimize(greedy_result, freights, vehicles, time_limit=10.0)

println("Initial (greedy): ", improved.initial_objective, " km")
println("Improved (local search): ", improved.objective_value, " km")
println("Improvement: ", improved.improvement, "%")

# Generate route map
generate_route_map(improved.freight_results, vehicles, "improved_route_map.html")
```

### MILP Optimization

```julia
using FreightDispatchSimulator
using CSV, DataFrames

# Load data
freights = CSV.read("data/urban/freights.csv", DataFrame)
vehicles = CSV.read("data/urban/vehicles.csv", DataFrame)

# Find optimal solution
result = optimize_dispatch(freights, vehicles, time_limit=60.0)

println("Optimal distance: ", result.objective_value, " km")
println("Solve time: ", result.solve_time, " seconds")

# Generate route map from MILP results
generate_route_map(result.freight_results, vehicles, "optimal_route_map.html")
```

## Solution Approaches

This package implements three solution approaches with different tradeoffs between solution quality and computational cost. See `SOLUTION_APPROACHES.md` for detailed theory.

### Greedy Heuristics

Fast algorithms that make locally optimal decisions. Implemented in `src/strategies.jl`:

| Strategy | Selection Criterion | Best Use Case |
|----------|---------------------|---------------|
| **FCFS** | First available vehicle | Simple, predictable allocation |
| **Cost** | Closest vehicle to pickup | Minimize empty miles |
| **Distance** | Shortest total route distance | Minimize fuel consumption |
| **OverallCost** | Fastest route completion (accounts for speed) | Time-sensitive deliveries |

**Characteristics:**
- ⚡ Millisecond response times
- 📈 Linear scalability (handles 100+ freights)
- ✅ 2-10% from optimal on typical problems
- 🎯 Best for real-time/online decision-making

### Local Search (Metaheuristic)

Iteratively improves greedy solutions through local search. Implemented in `src/LocalSearch.jl`:

**How it works:**
1. Start with greedy solution (fast initialization)
2. Explore neighborhood by swapping freight assignments
3. Accept improvements until local optimum reached

**Characteristics:**
- ⚡ Seconds response time (0.1-2s typical)
- 📊 Improves greedy by 2-5% on average
- ✅ 0-5% from optimal on typical problems
- 🎯 Best balance between quality and speed

### MILP Optimization

Exact optimization using Mixed Integer Linear Programming. Implemented in `src/MILPOptimizer.jl`:

**Characteristics:**
- ✓ Provably optimal solutions (0% gap)
- ⏱️ Seconds to minutes solving time
- 📉 Exponential complexity (struggles with >20 freights)
- 🎯 Best for batch/offline planning

### When to Use Each:

| Criterion | Greedy | Local Search | MILP |
|-----------|--------|--------------|------|
| Problem Size | 50+ freights | 10-50 freights | <20 freights |
| Response Time | <0.01s | 0.1-2s | Minutes OK |
| Solution Quality | 2-10% gap | 0-5% gap | Optimal (0%) |
| Use Case | Real-time | Balanced | Strategic |
| All freights known? | No (online) | Yes (batch) | Yes (batch) |

**Recommendation:** For most applications, **Local Search** offers the best tradeoff between solution quality and computational cost.

## Command Line Interface

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
# Run greedy strategy
julia --project=. scripts/main.jl data/test0 Distance results.csv -m route_map.html

# Show help
julia --project=. scripts/main.jl --help
```

## Examples and Visualizations

### Greedy Strategy Comparison
`examples.ipynb` - Compare all four greedy strategies:
- Performance metrics (distance, utilization, success rates)
- Interactive charts and graphs
- Route map generation
- Multi-dataset analysis

### Full Solution Approach Comparison
`examples_milp_comparison.ipynb` - Compare all three approaches:
- Greedy vs Local Search vs MILP
- Optimality gap analysis (how close to optimal)
- Solving time comparisons (computational cost)
- Scalability tradeoffs
- When to use each approach

### Theoretical Background
`SOLUTION_APPROACHES.md` - Deep dive into algorithms:
- Problem formulation and complexity
- Detailed explanation of each approach
- MILP mathematical model
- Metaheuristic algorithms
- Hybrid approaches
- References and further reading

To run the notebooks:
```bash
# Start Jupyter with the project environment
julia --project=. -e 'using IJulia; notebook(dir=pwd())'
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

## Interactive Visualization

The package generates interactive HTML maps with clear color-coding by vehicle:

### Map Elements:
- **Route Lines**: Each vehicle has a unique color showing its path
- **⚫ Pickup Points**: Circles at freight pickup locations (color-matched to vehicle)
- **■ Delivery Points**: Squares at freight delivery locations (color-matched to vehicle)
- **⬡ Vehicle Bases**: Hexagons showing where vehicles start/return (color-matched to vehicle)
- **❌ Failed Freight**: Red X marks for unassigned freights
- **Hover Info**: Mouse over any element for detailed information

### How to Read the Map:
1. Each vehicle has a consistent color throughout (routes, pickups, deliveries, base)
2. Follow a single color to see one vehicle's entire route
3. Circles indicate where freights are picked up
4. Squares indicate where freights are delivered
5. Hexagons indicate vehicle bases
6. Failed freights show as red X at their pickup location

The map title shows total freights and how many were successfully assigned vs failed.

## Included Datasets

```
data/
├── urban/          # US: NYC urban deliveries (15 freights, 5 vehicles)
├── longhaul/       # US: Cross-country routes (8 freights, 3 vehicles)
├── mixed/          # US: Combined urban & long-haul (20 freights, 6 vehicles)
├── eu_urban/       # EU: Netherlands cities (12 freights, 4 vehicles)
├── eu_longhaul/    # EU: Cross-Europe routes (10 freights, 4 vehicles)
├── iberia/         # Iberia: Spain & Portugal (15 freights, 5 vehicles)
├── benelux/        # Benelux: NL/BE/LU region (12 freights, 4 vehicles)
├── test0/          # Basic test data (2 freights, 2 vehicles)
├── test1/          # Iberian test data (20 freights, 15 vehicles)
└── test_failure/   # Failure scenario data
```

## Performance Comparison

Typical results from example datasets:

| Dataset | Size | Greedy Distance | MILP Optimal | Gap | Greedy Time | MILP Time |
|---------|------|-----------------|--------------|-----|-------------|-----------|
| test0 | 2F, 2V | 13,842 km | 13,842 km | 0% | 0.002s | 0.07s |
| Urban | 15F, 5V | ~266 km | ~260 km | 2% | 0.2s | 0.5s |
| EU Urban | 12F, 4V | ~250 km | ~240 km | 4% | 0.1s | 0.3s |
| Iberia | 15F, 5V | ~3,500 km | ~3,400 km | 3% | 0.2s | 1.5s |

*F=Freights, V=Vehicles*

**Key Insights:**
- Greedy Distance strategy typically achieves 0-5% optimality gap
- MILP provides provably optimal solutions at higher computational cost
- Greedy scales to large problems; MILP best for <20 freights

## Testing

Run the test suite:
```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

The tests cover:
- Greedy dispatch strategies
- MILP optimization
- Visualization generation
- CLI interface
- Data integrity

## Project Structure

```
freight-dispatch-simulator/
├── Project.toml                      # Package configuration
├── Manifest.toml                     # Dependency lock file
├── README.md                         # This file
├── examples.ipynb                    # Greedy strategy comparisons
├── examples_milp_comparison.ipynb    # Greedy vs MILP analysis
├── src/
│   ├── FreightDispatchSimulator.jl  # Main module
│   ├── types.jl                      # Data structures
│   ├── distances.jl                  # Haversine distance
│   ├── strategies.jl                 # Greedy strategies
│   ├── dispatcher.jl                 # Dispatcher logic
│   ├── vehicle.jl                    # Vehicle process
│   ├── simulation.jl                 # Simulation orchestration
│   ├── MapVisualization.jl           # Route visualization
│   └── MILPOptimizer.jl             # MILP optimization
├── test/
│   └── runtests.jl                  # Test suite
├── scripts/
│   └── main.jl                      # CLI interface
└── data/                            # Example datasets
```

## Dependencies

- `CSV.jl`: CSV file handling
- `DataFrames.jl`: Data manipulation
- `SimJulia.jl`: Discrete event simulation
- `JuMP.jl`: Mathematical optimization
- `HiGHS.jl`: MILP solver
- `Plots.jl`: Plotting infrastructure
- `PlotlyJS.jl`: Interactive visualization
- `Colors.jl`: Color handling
- `ResumableFunctions.jl`: Coroutine support

## Contributing

Code should follow Julia formatting conventions:
```bash
julia --project=. -e 'using JuliaFormatter; format_file("filename.jl")'
```

Contributions are welcome! Please open an issue to discuss major changes.

## Future Work

- **Metaheuristics**: Simulated annealing, genetic algorithms, ant colony optimization
- **Machine Learning**: Learn dispatch policies from historical data
- **Multi-objective Optimization**: Balance distance, time, cost, emissions
- **Dynamic Reassignment**: Allow in-flight route adjustments
- **Stochastic Models**: Account for uncertainty in travel times

## License

This project is licensed under the MIT License.
