using Test, AdvancedHMC, LinearAlgebra, UnicodePlots, Random
using Statistics: mean, var, cov
include("common.jl")

@testset "Matrix mode" begin
    n_chains_max = 20
    n_chains_list = collect(1:n_chains_max)
    θ_init_list = [rand(D, n_chains) for n_chains in n_chains_list]
    ϵ = 0.1
    lf = Leapfrog(ϵ)
    i_test = 5
    lfi = Leapfrog(fill(ϵ, i_test))
    lfi_jittered = JitteredLeapfrog(fill(ϵ, i_test), 1.0)
    n_steps = 10
    n_samples = 20_000
    n_adapts = 4_000

    for metricT in [
        UnitEuclideanMetric,
        DiagEuclideanMetric,
        DenseEuclideanMetric,
    ], κ in [
        HMCKernel(Trajectory(lfi, FixedNSteps(n_steps)), MetropolisTS),
        HMCKernel(Trajectory(lfi, FixedNSteps(n_steps)), MultinomialTS),
        HMCKernel(Trajectory(lfi_jittered, FixedNSteps(n_steps)), MetropolisTS),
        HMCKernel(Trajectory(lfi_jittered, FixedNSteps(n_steps)), MultinomialTS),
        HMCKernel(Trajectory(lf, FixedIntegrationTime(ϵ * n_steps)), MetropolisTS),
        HMCKernel(Trajectory(lf, FixedIntegrationTime(ϵ * n_steps)), MultinomialTS),
    ]
        metricT <: DenseEuclideanMetric && continue

        n_chains = n_chains_list[i_test]
        metric = metricT((D, n_chains))
        h = Hamiltonian(metric, ℓπ, ∂ℓπ∂θ)
        @test show(metric) == nothing; println()
        @test show(h) == nothing; println()
        @test show(κ) == nothing; println()

        # NoAdaptation
        Random.seed!(100)
        samples, stats = sample(h, κ, θ_init_list[i_test], n_samples; verbose=false)
        @test mean(samples) ≈ zeros(D, n_chains) atol=RNDATOL * n_chains

        # Adaptation
        for adaptor in [
            MassMatrixAdaptor(metric),
            StepSizeAdaptor(0.8, lfi),
            NaiveHMCAdaptor(
                MassMatrixAdaptor(metric),
                StepSizeAdaptor(0.8, lfi),
            ),
            StanHMCAdaptor(
                MassMatrixAdaptor(metric),
                StepSizeAdaptor(0.8, lfi),
            ),
        ]
            κ.τ.criterion isa FixedIntegrationTime && continue

            @test show(adaptor) == nothing; println()

            Random.seed!(100)
            samples, stats = sample(h, κ, θ_init_list[i_test], n_samples, adaptor, n_adapts; verbose=false, progress=false)
            @test mean(samples) ≈ zeros(D, n_chains) atol=RNDATOL * n_chains
        end

        # Passing a vector of same RNGs
        rng = [MersenneTwister(1) for _ in 1:n_chains]
        h = Hamiltonian(metricT((D, n_chains)), ℓπ, ∂ℓπ∂θ)
        θ_init = repeat(rand(D), 1, n_chains)
        samples, stats = sample(rng, h, κ, θ_init, n_samples; verbose=false)
        all_same = true
        for i_sample in 2:10
            for j in 2:n_chains
                all_same = all_same && samples[i_sample][:,j] == samples[i_sample][:,1]
            end
        end
        @test all_same
    end
    @info "Tests for `DenseEuclideanMetric` are skipped."
    @info "`FixedIntegrationTime` is NOT compatible with `JitteredLeapfrog`."
    @info "Adaptation tests for `FixedIntegrationTime` with `StepSizeAdaptor` are skipped."

    # Simple time benchmark
    let metricT=UnitEuclideanMetric
        κ = HMCKernel(Trajectory(lf, FixedNSteps(n_steps)), MetropolisTS)

        time_vec = Vector{Float64}(undef, n_chains_max)
        for (i, n_chains) in enumerate(n_chains_list)
            h = Hamiltonian(metricT((D, n_chains)), ℓπ, ∂ℓπ∂θ)
            t = @elapsed samples, stats = sample(h, κ, θ_init_list[i], n_samples; verbose=false)
            time_vec[i] = t
        end

        # Time for multiple runs of single chain
        time_loop = Vector{Float64}(undef, n_chains_max)

        for (i, n_chains) in enumerate(n_chains_list)
            t = @elapsed for j in 1:n_chains
                h = Hamiltonian(metricT(D), ℓπ, ∂ℓπ∂θ)
                samples, stats = sample(h, κ, θ_init_list[i][:,j], n_samples; verbose=false)
            end
            time_loop[i] = t
        end

        # Make plot
        p = lineplot(
            collect(1:n_chains_max),
            time_vec;
            title="Scalabiliry of multiple chains",
            name="Vectorization",
            xlabel="Num of chains",
            ylabel="Time (s)"
        )
        lineplot!(p, collect(n_chains_list), time_loop; color=:blue, name="Loop")
        println(); show(p); println(); println()
    end
end
