include("../src/FreightDispatchSimulator.jl")

using .FreightDispatchSimulator
using DataFrames, CSV
using Base.Meta

# Constant dictionary mapping strategy names to descriptions
const AVAILABLE_STRATEGIES = Dict(
    "FCFS" => ("First Come, First Served - dispatches in order of arrival", "FCFSStrategy"),
    "Cost" => ("Cost-based dispatching - prioritizes by cost efficiency", "CostStrategy"),
    "Distance" => ("Distance-based dispatching - prioritizes by proximity", "DistanceStrategy"),
    "OverallCost" => ("Overall cost optimization - considers total system cost", "OverallCostStrategy")
)

# Function to show available strategies
function show_available_strategies()
    println("Available dispatch strategies:")
    for (name, (description, _)) in AVAILABLE_STRATEGIES
        println("  $name: $description")
    end
    println()
end

# Function to determine dispatch strategy
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

# Main function
function main()
    args = Base.ARGS

    # Check for --help or -h as first argument
    if length(args) > 0 && (args[1] == "--help" || args[1] == "-h")
        println("Usage: julia main.jl <input_directory> <dispatcher_type> <output_file> [-m [map_file]]")
        println("       julia main.jl --help")
        println("       julia main.jl -h")
        println()
        println("Arguments:")
        println("  input_directory   Directory containing freights.csv and vehicles.csv")
        println("  dispatcher_type   Dispatch strategy to use")
        println("  output_file       Output CSV file path for freight results")
        println()
        println("Options:")
        println("  -m [map_file]     Generate route map visualization (optional HTML file path)")
        println("                    If no path provided, defaults to <output_file>_map.html")
        println()
        show_available_strategies()
        exit(0)
    end

    # Show available strategies before parsing args
    show_available_strategies()

    if length(args) < 3
        println("Usage: julia main.jl <input_directory> <dispatcher_type> <output_file> [-m [map_file]]")
        println("       julia main.jl --help")
        println("       julia main.jl -h")
        return nothing
    end

    # Parse command-line arguments
    input_dir = args[1]
    dispatcher_type = args[2]
    output_file = args[3]
    
    # Parse optional map generation flag
    generate_map = false
    map_output_file = ""
    
    # Check for -m flag in remaining arguments
    remaining_args = args[4:end]
    i = 1
    while i <= length(remaining_args)
        if remaining_args[i] == "-m"
            generate_map = true
            # Check if next argument is a file path (doesn't start with -)
            if i + 1 <= length(remaining_args) && !startswith(remaining_args[i + 1], "-")
                map_output_file = remaining_args[i + 1]
                i += 2
            else
                # Default to replacing .csv with _map.html
                map_output_file = replace(output_file, ".csv" => "_map.html")
                i += 1
            end
        else
            println("Warning: Unknown argument '", remaining_args[i], "'")
            i += 1
        end
    end

    # Validate dispatcher_type
    if !haskey(AVAILABLE_STRATEGIES, dispatcher_type)
        println("Error: Unknown dispatcher type '$dispatcher_type'")
        println()
        show_available_strategies()
        exit(1)
    end

    # Load data
    freights_df = CSV.read(joinpath(input_dir, "freights.csv"), DataFrame)
    vehicles_df = CSV.read(joinpath(input_dir, "vehicles.csv"), DataFrame)

    # Get dispatch strategy
    strategy = get_strategy(dispatcher_type)
    
    # Show selected strategy information
    println("Using dispatch strategy: ", dispatcher_type, " :: ", typeof(strategy))
    println()

    # Run the simulation
    freight_results_df, vehicle_aggregates_df = Simulation(
        freights_df, vehicles_df, 3600.0, strategy
    )

    # Output results
    println("\nFreight Results:")
    println(freight_results_df)

    println("\nVehicle Aggregates:")
    println(vehicle_aggregates_df)

    # Write freight results
    CSV.write(output_file, freight_results_df)

    # Write vehicle aggregates to a separate file
    vehicle_output_file = replace(output_file, ".csv" => "_vehicles.csv")
    CSV.write(vehicle_output_file, vehicle_aggregates_df)

    println("\nResults written to:")
    println("  Freight results: ", output_file)
    println("  Vehicle aggregates: ", vehicle_output_file)
    
    # Generate route map if requested
    if generate_map
        println("\nGenerating route map...")
        
        # Merge freight results with original freight data to get coordinates
        # Join on freight ID to get pickup/delivery coordinates
        freight_results_with_coords = leftjoin(
            freight_results_df, 
            freights_df, 
            on = :freight_id => :id,
            makeunique = true
        )
        
        generate_route_map(
            freight_results_with_coords,
            vehicles_df,
            map_output_file;
            show_failures=true
        )
        println("  Route map: ", map_output_file)
    end
end

# Run the main function
main()
