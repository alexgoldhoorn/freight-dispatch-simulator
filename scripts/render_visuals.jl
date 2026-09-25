# Regenerate the visual assets in docs/:
#   docs/maps/*.html            interactive route maps
#   docs/replay/iberia.html     animated greedy-vs-MILP replay (open in a browser)
#   docs/assets/timeline_iberia.svg  vehicle timelines, greedy vs MILP
#
#   julia --project=. scripts/render_visuals.jl
#
# The README GIF (docs/assets/replay_iberia.gif) is captured from the replay page
# with scripts/capture/capture_replay.js; see the comment at the top of that file.

using FreightDispatchSimulator

const ROOT = joinpath(@__DIR__, "..")
docs = joinpath(ROOT, "docs")

for name in ["iberia", "eu_urban", "urban"]
    inst = load_instance(joinpath(ROOT, "data", name))
    greedy = simulate(inst, DistanceStrategy())
    best = optimize_dispatch(inst; time_limit = 60)
    generate_route_map(greedy, inst, joinpath(docs, "maps", "$(name)_distance.html"); title = "$(name) · greedy Distance")
    generate_route_map(best, inst, joinpath(docs, "maps", "$(name)_milp.html"); title = "$(name) · MILP")
    if name == "iberia"
        generate_timeline([greedy, best], inst, joinpath(docs, "assets", "timeline_iberia.svg");
            title = "Iberia: the same 15 freights, two plans")
        generate_replay([greedy, best], inst, joinpath(docs, "replay", "iberia.html");
            title = "Iberia · 15 freights, 5 trucks: greedy vs MILP")
    end
    println("$(name): greedy $(round(greedy.kpis.objective)) vs MILP $(round(best.kpis.objective))")
end
