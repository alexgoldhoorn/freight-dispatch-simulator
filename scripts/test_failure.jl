include("../src/FreightSimulator2.jl")

using .FreightSimulator2
using DataFrames, CSV

# Load test data with a freight that exceeds vehicle capacity
freights_df = CSV.read("data/test_failure/freights.csv", DataFrame)
vehicles_df = CSV.read("data/test_failure/vehicles.csv", DataFrame)

println("Testing FCFS Dispatcher with failure case...")
println("Freights:")
println(freights_df)
println("\nVehicles:")
println(vehicles_df)

# Run the simulation
results_df = run_simulation(freights_df, vehicles_df)

println("\n", results_df)
