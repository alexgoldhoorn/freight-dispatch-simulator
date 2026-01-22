"""
    FreightDispatchSimulator

A Julia package for simulating freight delivery systems with both greedy heuristics
and exact optimization, featuring interactive visualization capabilities.

# Features
- Greedy dispatch strategies: FCFS, Cost, Distance, OverallCost
- MILP exact optimization: Provably optimal solutions using JuMP + HiGHS
- Interactive route visualization with PlotlyJS
- Discrete event simulation using SimJulia
- Comprehensive performance metrics and comparisons

# Quick Start - Greedy Heuristic
```julia
using FreightDispatchSimulator
using CSV, DataFrames

# Load data
freights_df = CSV.read("freights.csv", DataFrame)
vehicles_df = CSV.read("vehicles.csv", DataFrame)

# Run simulation with greedy strategy
freight_results, vehicle_aggregates = Simulation(
    freights_df,
    vehicles_df,
    3600.0,  # return to base buffer
    DistanceStrategy()
)

# Generate interactive route map
generate_route_map(freight_results, vehicles_df, "route_map.html")
```

# Quick Start - MILP Optimization
```julia
using FreightDispatchSimulator
using CSV, DataFrames

# Load data
freights = CSV.read("freights.csv", DataFrame)
vehicles = CSV.read("vehicles.csv", DataFrame)

# Find optimal solution
result = optimize_dispatch(freights, vehicles, time_limit=60.0)

println("Optimal distance: ", result.objective_value, " km")
generate_route_map(result.freight_results, vehicles, "optimal_map.html")
```

# Exports
The module exports types, strategies, simulation functions, optimization, and visualization.
"""
module FreightDispatchSimulator

# Import required packages
using CSV
using DataFrames
using Dates
using JSON3
using SimJulia
using ResumableFunctions

# Export types
export Freight,
    Vehicle,
    VehicleState,
    VehicleInfo,
    FreightResult,
    VehicleAggregate

# Export utility functions
export get_base_location,
    haversine,
    sim_seconds

# Export dispatch strategies
export DispatchStrategy,
    FCFSStrategy,
    CostStrategy,
    DistanceStrategy,
    OverallCostStrategy

# Export main simulation function
export Simulation

# Export visualization
export generate_route_map

# Export MILP optimization
export optimize_dispatch,
    MILPResult

# Include all module files in dependency order
include("distances.jl")
include("types.jl")
include("strategies.jl")
include("dispatcher.jl")
include("vehicle.jl")
include("simulation.jl")
include("MapVisualization.jl")
include("MILPOptimizer.jl")

end # module FreightDispatchSimulator
