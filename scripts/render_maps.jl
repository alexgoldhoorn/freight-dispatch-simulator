# Write example route maps to docs/maps/ (open them in a browser).
#
#   julia --project=. scripts/render_maps.jl

using FreightDispatchSimulator

const ROOT = joinpath(@__DIR__, "..")
outdir = joinpath(ROOT, "docs", "maps")

for name in ["iberia", "eu_urban", "urban"]
    inst = load_instance(joinpath(ROOT, "data", name))
    greedy = simulate(inst, DistanceStrategy())
    best = optimize_dispatch(inst; time_limit = 60)
    generate_route_map(greedy, inst, joinpath(outdir, "$(name)_distance.html"); title = "$(name) · greedy Distance")
    generate_route_map(best, inst, joinpath(outdir, "$(name)_milp.html"); title = "$(name) · MILP")
    println("$(name): greedy $(round(greedy.kpis.objective)) vs MILP $(round(best.kpis.objective))")
end
