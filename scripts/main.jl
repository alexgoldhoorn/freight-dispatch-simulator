# Command line interface
#
#   julia --project=. scripts/main.jl <input_directory> <method> <output_file.csv> [-m [map.html]]
#   julia --project=. scripts/main.jl --help

using FreightDispatchSimulator
using CSV, DataFrames

const METHODS = [
    "FCFS" => "greedy: first idle vehicle, else the one free first",
    "Cost" => "greedy: nearest idle vehicle to the pickup",
    "Distance" => "greedy: idle vehicle with the shortest full trip",
    "OverallCost" => "greedy: earliest estimated delivery (considers queues)",
    "LocalSearch" => "relocate/swap local search from the best greedy rule",
    "MILP" => "exact MILP (JuMP + HiGHS), 60 s time limit",
    "compare" => "run all of the above and print a comparison table",
]

function usage(io = stdout)
    println(io, "Usage: julia --project=. scripts/main.jl <input_directory> <method> <output_file.csv> [-m [map.html]]")
    println(io)
    println(io, "  input_directory   directory with freights.csv and vehicles.csv")
    println(io, "  method            one of the methods below")
    println(io, "  output_file.csv   per-freight results; vehicle totals go to <output_file>_vehicles.csv")
    println(io, "  -m [map.html]     also write an interactive route map (default <output_file>_map.html)")
    println(io)
    println(io, "Methods:")
    for (name, description) in METHODS
        println(io, "  ", rpad(name, 12), description)
    end
end

function run_method(inst, method)
    method in first.(FreightDispatchSimulator.GREEDY_STRATEGIES) &&
        return simulate(inst, Dict(FreightDispatchSimulator.GREEDY_STRATEGIES)[method])
    method == "LocalSearch" && return compare_methods(inst; methods = [:greedy, :local_search])[2][end]
    method == "MILP" && return optimize_dispatch(inst; time_limit = 60)
    error("unknown method $(method)")
end

function main(args)
    if isempty(args) || args[1] in ("-h", "--help")
        usage()
        return 0
    end
    if length(args) < 3 || !(args[2] in first.(METHODS))
        length(args) >= 2 && println(stderr, "Unknown method '$(args[2])'\n")
        usage(stderr)
        return 1
    end
    input_dir, method, output_file = args[1:3]
    map_file = nothing
    rest = args[4:end]
    if !isempty(rest) && rest[1] == "-m"
        map_file = length(rest) >= 2 ? rest[2] : replace(output_file, r"\.csv$" => "") * "_map.html"
    elseif !isempty(rest)
        println(stderr, "Unknown argument '$(rest[1])'")
        return 1
    end

    inst = load_instance(input_dir)
    println("Instance: $(length(inst.freights)) freights, $(length(inst.vehicles)) vehicles")

    result = if method == "compare"
        table, results = compare_methods(inst)
        show(stdout, table; allrows = true, summary = false, eltypes = false)
        println()
        results[argmin([r.kpis.objective for r in results])]
    else
        run_method(inst, method)
    end
    println(result)

    CSV.write(output_file, result.freight_results)
    vehicles_file = replace(output_file, r"\.csv$" => "") * "_vehicles.csv"
    CSV.write(vehicles_file, result.vehicle_aggregates)
    println("Wrote $(output_file) and $(vehicles_file)")
    if map_file !== nothing
        generate_route_map(result, inst, map_file)
        println("Wrote $(map_file)")
    end
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
