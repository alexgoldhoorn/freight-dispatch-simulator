"""
    FreightDispatchSimulator

Discrete-event simulation of freight dispatching, with greedy online rules, a
local search metaheuristic and an exact MILP. Every method is evaluated by
replaying its assignment in the same simulation, so the numbers are comparable.

```julia
using FreightDispatchSimulator

inst = load_instance("data/iberia")
greedy = simulate(inst, DistanceStrategy())
ls = local_search_optimize(inst; initial = greedy)
milp = optimize_dispatch(inst; time_limit = 60)
table, _ = compare_methods(inst)
generate_route_map(milp, inst, "route_map.html")
```
"""
module FreightDispatchSimulator

using CSV
using DataFrames
using Dates
using HiGHS
using JSON
using JuMP
using Random
using ResumableFunctions
import ConcurrentSim

export Freight, Vehicle, Instance, Trip, ObjectiveWeights, DispatchResult
export load_instance, haversine, travel_time_s, sim_seconds
export DispatchStrategy, FCFSStrategy, CostStrategy, DistanceStrategy, OverallCostStrategy,
    FixedAssignment, GREEDY_STRATEGIES, strategy_name
export simulate, evaluate_assignment, evaluate_plan, Simulation
export local_search_optimize, optimize_dispatch
export compare_methods, generate_instance
export generate_route_map

include("distances.jl")
include("types.jl")
include("schedule.jl")
include("strategies.jl")
include("simulation.jl")
include("LocalSearch.jl")
include("MILPOptimizer.jl")
include("experiments.jl")
include("MapVisualization.jl")

end # module
