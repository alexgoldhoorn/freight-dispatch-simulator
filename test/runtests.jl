using Test
using CSV
using DataFrames

# Include the module
include("../src/FreightDispatchSimulator.jl")
using .FreightDispatchSimulator

@testset "FreightDispatchSimulator.jl Tests" begin
    @testset "Basic simulation test with test0 data" begin
        # Load test0 data
        freights_df = CSV.read("../data/test0/freights.csv", DataFrame)
        vehicles_df = CSV.read("../data/test0/vehicles.csv", DataFrame)

        # Run simulation using the new Simulation function
        freight_results_df, vehicle_aggregates_df =
            Simulation(freights_df, vehicles_df, 3600.0, FCFSStrategy())

        # Test that all freights are assigned
        @test nrow(freight_results_df) == nrow(freights_df)
        @test all(freight_results_df.success)
        @test all(freight_results_df.assigned_vehicle .!== nothing)

        # Test that we have the expected number of vehicles
        @test nrow(vehicle_aggregates_df) == nrow(vehicles_df)

        # Test that freight IDs match
        expected_freight_ids = Set(string.(freights_df.id))
        actual_freight_ids = Set(freight_results_df.freight_id)
        @test expected_freight_ids == actual_freight_ids

        # Test that vehicle IDs match
        expected_vehicle_ids = Set(string.(vehicles_df.id))
        actual_vehicle_ids = Set(vehicle_aggregates_df.vehicle_id)
        @test expected_vehicle_ids == actual_vehicle_ids

        println("✓ All freights successfully assigned")
        println("✓ Freight results: ", nrow(freight_results_df), " records")
        println("✓ Vehicle aggregates: ", nrow(vehicle_aggregates_df), " records")
    end

    @testset "Test different dispatch strategies" begin
        # Load test0 data
        freights_df = CSV.read("../data/test0/freights.csv", DataFrame)
        vehicles_df = CSV.read("../data/test0/vehicles.csv", DataFrame)

        strategies =
            [FCFSStrategy(), CostStrategy(), DistanceStrategy(), OverallCostStrategy()]
        strategy_names = ["FCFS", "Cost", "Distance", "OverallCost"]

        for (strategy, name) in zip(strategies, strategy_names)
            @testset "Strategy: $name" begin
                freight_results_df, vehicle_aggregates_df =
                    Simulation(freights_df, vehicles_df, 3600.0, strategy)

                # Test that all freights are assigned
                @test nrow(freight_results_df) == nrow(freights_df)
                @test all(freight_results_df.success)
                @test all(freight_results_df.assigned_vehicle .!== nothing)

                println("✓ Strategy $name: All freights assigned")
            end
        end
    end

    @testset "CLI help functionality" begin
        # Test that CLI help command exits successfully
        result = run(`julia -e 'include("scripts/main.jl")' --help`; wait = false)
        wait(result)
        @test result.exitcode == 0
        println("✓ CLI --help command exits successfully")

        # Test that CLI -h command also exits successfully
        result = run(`julia -e 'include("scripts/main.jl")' -h`; wait = false)
        wait(result)
        @test result.exitcode == 0
        println("✓ CLI -h command exits successfully")
    end
end
