using Test
using CSV
using DataFrames
using FreightDispatchSimulator

const DATA = joinpath(@__DIR__, "..", "data")
const ROOT = joinpath(@__DIR__, "..")

read_dataset(name) = (CSV.read(joinpath(DATA, name, "freights.csv"), DataFrame),
                      CSV.read(joinpath(DATA, name, "vehicles.csv"), DataFrame))

@testset "FreightDispatchSimulator" begin
    @testset "haversine" begin
        @test haversine(0, 0, 0, 0) == 0
        @test isapprox(haversine(40.7128, -74.0060, 34.0522, -118.2437), 3936; atol = 5)  # NYC -> LA
        @test isapprox(haversine(41.3851, 2.1734, 40.4168, -3.7038), 505; atol = 5)       # BCN -> MAD
    end

    @testset "loading does not modify inputs" begin
        f, v = read_dataset("urban")
        f0, v0 = copy(f), copy(v)
        inst = load_instance(f, v)
        simulate(f, v, DistanceStrategy())
        @test f == f0 && names(f) == names(f0)
        @test v == v0
        @test issorted([x.ready_s for x in inst.freights])
        @test inst.freights[1].ready_s == 0
    end

    @testset "all greedy strategies on every dataset" begin
        for name in readdir(DATA)
            inst = load_instance(joinpath(DATA, name))
            for (sname, s) in GREEDY_STRATEGIES
                r = simulate(inst, s)
                k = r.kpis
                @test nrow(r.freight_results) == length(inst.freights)
                @test nrow(r.vehicle_aggregates) == length(inst.vehicles)
                @test all(0 .<= r.vehicle_aggregates.utilization_rate .<= 1 + 1e-9)
                @test k.n_served + k.n_unserved == k.n_freights
                @test sum(r.vehicle_aggregates.total_freights_handled) == k.n_served
                @test isapprox(sum(r.vehicle_aggregates.total_distance_km), k.total_distance_km)
                # A freight is only unserved when no vehicle can carry it
                maxcap = maximum(v.capacity_kg for v in inst.vehicles)
                @test k.n_unserved == count(f -> f.weight_kg > maxcap, inst.freights)
                # Physical consistency of the recorded timeline
                served = filter(x -> x.success, r.freight_results)
                @test all(served.start_s .>= served.ready_s)
                @test all(served.pickup_s .<= served.delivered_s .<= served.back_at_base_s)
                @test all(served.lateness_s .== max.(0, served.delivered_s .- served.due_s))
            end
        end
    end

    @testset "deterministic" begin
        inst = load_instance(joinpath(DATA, "mixed"))
        for (_, s) in GREEDY_STRATEGIES
            @test simulate(inst, s).assignment == simulate(inst, s).assignment
        end
    end

    @testset "busy vehicles queue instead of failing" begin
        f = DataFrame(id = ["A", "B", "C"], weight_kg = [10.0, 10.0, 10.0],
            pickup_lat = [41.0, 41.0, 41.0], pickup_lon = [2.0, 2.0, 2.0],
            delivery_lat = [41.5, 41.5, 41.5], delivery_lon = [2.0, 2.0, 2.0],
            pickup_time = [0.0, 0.0, 0.0], delivery_time = [3600.0, 3600.0, 3600.0])
        v = DataFrame(id = ["V1"], start_lat = [41.0], start_lon = [2.0], capacity_kg = [100.0], speed_km_per_hour = [60.0])
        r = simulate(f, v, FCFSStrategy())
        @test r.kpis.n_served == 3
        @test r.kpis.n_on_time == 1             # the queue makes B and C late
        @test r.kpis.total_lateness_h > 0
        @test issorted(r.freight_results.start_s)
    end

    @testset "capacity failure" begin
        r = simulate(joinpath(DATA, "test_failure"), FCFSStrategy())
        @test r.kpis.n_unserved == 1
        @test only(r.freight_results[.!r.freight_results.success, :freight_id]) == "F2"
    end

    @testset "vehicles return to their own base" begin
        f = DataFrame(id = ["A"], weight_kg = [1.0], pickup_lat = [41.0], pickup_lon = [2.0],
            delivery_lat = [41.2], delivery_lon = [2.0], pickup_time = [0.0], delivery_time = [1e5])
        v = DataFrame(id = ["V1"], start_lat = [41.0], start_lon = [2.0], base_lat = [41.5], base_lon = [2.0],
            capacity_kg = [10.0], speed_km_per_hour = [60.0])
        r = simulate(f, v, FCFSStrategy())
        expected = haversine(41.0, 2.0, 41.0, 2.0) + haversine(41.0, 2.0, 41.2, 2.0) + haversine(41.2, 2.0, 41.5, 2.0)
        @test isapprox(r.kpis.total_distance_km, expected)
    end

    @testset "simulation and analytic evaluator agree" begin
        for name in ["urban", "mixed", "iberia", "test1"], seed in 1:5
            inst = load_instance(joinpath(DATA, name))
            rng = FreightDispatchSimulator.Random.Xoshiro(seed)
            a = map(inst.freights) do f
                c = [j for (j, v) in enumerate(inst.vehicles) if v.capacity_kg >= f.weight_kg]
                isempty(c) ? 0 : rand(rng, c)
            end
            analytic = evaluate_plan(inst, a)
            des = evaluate_assignment(inst, FreightDispatchSimulator.assignment_dict(inst, a)).kpis
            for key in keys(analytic)
                @test isapprox(getfield(analytic, key), getfield(des, key); rtol = 1e-9, atol = 1e-6)
            end
        end
    end

    @testset "evaluate_assignment rejects infeasible assignments" begin
        inst = load_instance(joinpath(DATA, "test_failure"))
        @test_throws ArgumentError evaluate_assignment(inst, Dict("F2" => "V1"))
        @test_throws ArgumentError evaluate_assignment(inst, Dict("F1" => "nope"))
    end

    @testset "local search never worsens the start" begin
        for name in ["urban", "eu_urban", "benelux"]
            inst = load_instance(joinpath(DATA, name))
            for (_, s) in GREEDY_STRATEGIES
                g = simulate(inst, s)
                ls = local_search_optimize(inst; initial = g, time_limit = 10)
                @test ls.kpis.objective <= g.kpis.objective + 1e-6
                @test isapprox(ls.info.initial_objective, g.kpis.objective)
            end
        end
    end

    @testset "MILP matches the simulation and beats the heuristics" begin
        for name in ["test0", "longhaul", "eu_longhaul", "benelux"]
            inst = load_instance(joinpath(DATA, name))
            milp = optimize_dispatch(inst; time_limit = 60)
            @test milp.info.proven_optimal
            # The model objective is exactly what the simulation measures
            @test isapprox(milp.info.model_objective, milp.kpis.objective; rtol = 1e-6, atol = 1e-3)
            for (_, s) in GREEDY_STRATEGIES
                @test milp.kpis.objective <= simulate(inst, s).kpis.objective + 1e-6
            end
            @test milp.kpis.objective <= local_search_optimize(inst).kpis.objective + 1e-6
        end
    end

    @testset "MILP handles vehicles that start away from their base" begin
        f, v = generate_instance(6, 2; seed = 3)
        v.base_lat = v.start_lat .+ 0.3
        v.base_lon = v.start_lon .- 0.2
        inst = load_instance(f, v)
        milp = optimize_dispatch(inst; time_limit = 60)
        @test milp.info.proven_optimal
        @test isapprox(milp.info.model_objective, milp.kpis.objective; rtol = 1e-6, atol = 1e-3)
    end

    @testset "compare_methods and generator" begin
        f, v = generate_instance(8, 3; seed = 7)
        @test (f, v) == generate_instance(8, 3; seed = 7)
        table, results = compare_methods(f, v; milp_time_limit = 30)
        @test table.method == ["FCFS", "Cost", "Distance", "OverallCost", "LocalSearch", "MILP"]
        @test minimum(table.gap_to_best_pct) == 0
        @test all(table.gap_to_best_pct .>= 0)
    end

    @testset "route map" begin
        inst = load_instance(joinpath(DATA, "test_failure"))
        r = simulate(inst, DistanceStrategy())
        path = tempname() * ".html"
        generate_route_map(r, inst, path)
        html = read(path, String)
        @test occursin("scattergeo", html)
        @test occursin("Unserved", html)
        f, v = read_dataset("urban")
        fr, _ = Simulation(f, v, DistanceStrategy())
        @test generate_route_map(fr, v, path) == path
    end

    @testset "deprecated 4-argument Simulation still works" begin
        f, v = read_dataset("test0")
        fr, va = @test_deprecated Simulation(f, v, 3600.0, FCFSStrategy())
        @test all(fr.success)
    end

    @testset "CLI" begin
        julia = Base.julia_cmd()
        project = Base.active_project()
        script = joinpath(ROOT, "scripts", "main.jl")
        @test success(`$julia --project=$project $script --help`)
        out = tempname() * ".csv"
        @test success(pipeline(`$julia --project=$project $script $(joinpath(DATA, "urban")) Distance $out`; stdout = devnull))
        @test nrow(CSV.read(out, DataFrame)) == 15
    end
end
