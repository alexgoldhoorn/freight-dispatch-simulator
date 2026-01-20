"""
    FreightDispatchSimulator

A Julia package for simulating freight delivery systems with multiple dispatch strategies
and interactive visualization capabilities.

# Features
- Multiple dispatch strategies: FCFS, Cost-based, Distance-based, and Overall Cost
- Interactive route visualization with PlotlyJS
- Discrete event simulation using SimJulia
- Comprehensive performance metrics

# Quick Start
```julia
using FreightDispatchSimulator
using CSV, DataFrames

# Load data
freights_df = CSV.read("freights.csv", DataFrame)
vehicles_df = CSV.read("vehicles.csv", DataFrame)

# Run simulation with distance-based strategy
freight_results, vehicle_aggregates = Simulation(
    freights_df,
    vehicles_df,
    3600.0,  # return to base buffer
    DistanceStrategy()
)

# Generate interactive route map
generate_route_map(freight_results, vehicles_df, "route_map.html")
```

# Exports
The module exports types, strategies, simulation functions, and utilities.
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

# Include all module files in dependency order
include("distances.jl")
include("types.jl")
include("strategies.jl")
include("dispatcher.jl")
include("vehicle.jl")
include("simulation.jl")
include("MapVisualization.jl")

end # module FreightDispatchSimulator
