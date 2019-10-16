# Defining the observational scheme and parameters of the Markov chain

There is a series of objects that define the Markov chain Monte Carlo sampler
and that the user needs to define in order to be able to run the inference
algorithm. To keep this processes structured an object `MCMCSetup` is defined.
It allows for a systematic and concise way of defining the MCMC sampler.


## Defining the processes
To define the `MCMCSetup` one needs to decide on the `Target` diffusion an
`Auxiliary` diffusion and the observation scheme. For instance, suppose that
there are three observations:
```julia
obs = [...]
obs_times = [1.0, 2.0, 3.0]
```
Then the `target` diffusion is defined globally and the `auxiliary` diffusion
is defined separately on each interval
```julia
P_target = TargetDiffusion(parameters)
P_auxiliary = [AuxiliaryDiffusion(parameters, o, t) for (o,t) in zip(obs, obs_times)]
```
To define the setup for partially observed diffusion it is enough to write:
```julia
setup = MCMCSetup(P_target, P_auxiliary, PartObs()) # for first passage times use FPT()
```
```@docs
MCMCSetup
```

## Observations
To set the observations, apart from passing the observations and observation
times it is necessary to pass the observational operators and as well as
covariance of the noise. Additionally, one can pass additional information
about the first-passage scheme [TO DO add details on fpt].
```julia
L = ...
Σ = ...
set_observations!(setup, [L for _ in obs], [Σ for _ in obs], obs, obs_time)
```
```@docs
set_observations!
```

## Imputation grid
There are two objects that define the imputation grid. The time step `dt` and
the time transformation that transforms a regular time-grid with equidistantly
distributed imputation points. The second defaults to a usual transformation
employed in papers on the guided proposals. [TO DO add also space-time
transformation from the original paper for the bridges]. It is enough to call
```julia
dt = ...
set_imputation_grid!(setup, dt)
```
```@docs
set_imputation_grid!
```

## Transition kernels
To define the updates of the parameters and the Wiener path a couple of objects
need to specified. A boolean flag needs to be passed indicating whether any
parameter updates are to be performed. If set to `false` then only the path
is updated and the result it a marginal sampler on a path space. Additionally
a memory (or persistence) parameter of the preconditioned Crank-Nicolson scheme
needs to be set for the path updates. For the parameter updates three
additional objects must be specified. A sequence of transition kernels---one
for each Gibbs step, a sequence of lists indicating parameters to be
updated---one list for each Gibbs step and a sequence of indicators about the
types of parameter updates---one for each Gibbs step. Additionally, an object
describing an adaptation scheme for the auxiliary law can be passed [TODO add
description to the last]
### Random walk
The package provides an implementation of a `random walk`, which can be used
as a generic transition kernel
```@docs
RandomWalk
```
### Indicators for parameter update
The indicators for parameter updates should be in a format of tuple of tuples
(or arrays of arrays etc.). Each inner tuple corresponds to a single Gibbs step
and the elements of the inner tuples give indices of parameters that are to be
updated on a given Gibbs step. For instance: `((1,2,3),(5,))` says that in the
first Gibbs step the first three parameters are to be updated, whereas in the
second Gibbs step parameter `5` is to be updated.

### Flags for the types of parameter updates
There are currently two different ways of updating parameters:
```@docs
ConjugateUpdt
MetropolisHastingsUpdt
```

### Setting transition kernels
An example of setting the transition kernels is as follows:
```julia
pCN = ... # memory paramter of the preconditioned Crank Nicolson scheme
update_parameters = true
set_transition_kernels!(setup,
                        [RandomWalk([],[]),
                         RandomWalk([3.0, 5.0, 5.0, 0.01, 0.5], 5)],
                        pCN, update_parameters, ((1,2,3),(5,)),
                        (ConjugateUpdt(),
                         MetropolisHastingsUpdt(),
                        ))
```

```@docs
set_transition_kernels!
```


## Priors
Priors need to be defined for each Gibbs step (or more precisely for each
subset of parameters that is being updated). Additionally a prior over the
starting position needs to be defined as well. A few convenience functions for
the priors are provided by the package.

### Prior over the starting point
There are two types of priors for the starting point, either a `delta hit` at
some specified value, corresponding to a known starting point and a Gaussian
prior
```@docs
KnownStartingPt
GsnStartingPt
```

### Prior over the parameters
An improper flat prior is provided for quick tests:
```@docs
ImproperPrior
```
Additionally, as each Gibbs step needs to have its own set of priors
corresponding to the parameters being updated by this Gibbs step, the priors,
similarly to `indices of updated coordinates` need to be grouped into tuples
of tuples. To make this grouping easier on the user a `Priors` structure is
provided.
```@docs
Priors
```
#### Example 1

This is perhaps the most common use case. Suppose that `n` coordinates---where
we take `n=3` for illustration purposes---of prameter `θ` are being updated by
the Markov chain. Suppose further that there are `n` transition kernels, each
updating a separate coordinate. Let's assume for simplicity that each coordinate
is equipped with an independent, improper prior. Then the `Priors` struct can be
set up as follows:
```julia
n = 3
priors = Priors([ImproperPrior() for i in 1:n])

display(priors.priors)
(ImproperPrior(), ImproperPrior(), ImproperPrior())

display(priors.indicesForUpdt)
3-element Array{Array{Int64,1},1}:
 [1]
 [2]
 [3]
```
Notice that only a list of priors had to be supplied and the struct took care of
setting up the `indicesForUpdt` container.

#### Example 2
Suppose that the Markov chain uses two transition kernels. The first transition
kernel updates `3` coordinates of `θ`, which have a corresponding joint,
multivariate Normal prior with some pre-specified covariance matrix `Σ` and mean
`0`. The second transition kernel updates `2` coordinates of `θ`, and these two
are equipped with independent, improper priors. Then the `Priors` struct can be
set up as follows:
```julia
using LinearAlgebra, Distributions
Σ = diagm(0=>[1000.0, 1000.0, 1000.0])
μ = [0.0,0.0,0.0]
priors = Priors([MvNormal(μ, Σ), ImproperPrior(), ImproperPrior()],
                [[1],[2,3]])
display(priors.priors)
(FullNormal(
dim: 3
μ: [0.0, 0.0, 0.0]
Σ: [1000.0 0.0 0.0; 0.0 1000.0 0.0; 0.0 0.0 1000.0]
)\mutable struct
  fields
end
, ImproperPrior(), ImproperPrior())

display(priors.indicesForUpdt)
2-element Array{Array{Int64,1},1}:
 [1]   
 [2, 3]
```
Notice that we had to pass all priors in a list and then specify that the
first transition kernel uses only the first prior, whereas the second
transition kernel uses two priors from the list.

### Setting the priors
An example of setting the priors for two-step Gibbs sampler could be
```julia
μ, Σ, λ, Ω = ..., ..., ..., ...
set_priors!(setup, Priors((MvNormal(μ, Σ), ImproperPrior())), GsnStartingPt(λ, Ω), x0)
```
```@docs
set_priors!
```

## Blocking
Currently two choices of blocking are available:
* Either no blocking at all, which is the default behaviour of `set_blocking!`
```@docs
NoBlocking
```
* Or blocking using the chequerboard updating scheme.
```
ChequeredBlocking
```

For chequerboard updating scheme, at each observation a knot can be (but does
not have to be) placed. IMPORTANT: The knot indexing starts at the first
non-starting point observation. Suppose we have, say, `20` observations
(excluding the starting point). Let's put a knot on every other observation,
ending up with knots on observations with indices:
`[2,4,6,8,10,12,14,16,18,20]`. Chequerboard updating scheme splits these knots
into two, disjoint, interlaced subsets, i.e. `[2,6,10,14,18]` and
`[4,8,12,16,20]`. This also splits the path into two interlaced sets of blocks: `[1–2,3–6,7–10,11–14,15–18,19–20]`, `[1–4,5–8,9–12,13–16,17–20]` (where interval
indexing starts with interval 1, whose end-points are the starting point and the
first non-starting point observation). The path is updated in blocks. First,
blocks `[1–2,3–6,7–10,11–14,15–18,19–20]` are updated conditionally on full and
exact observations indexed with `[2,6,10,14,18]`, as well as all the remaining,
partial observations (indexed by `[1,2,3,...,20]`). Then, the other set of
blocks is updated in the same manner. This is then repeated. To define the
blocking behaviour, only the following needs to be written:
```julia
blocking = ChequeredBlocking()
blocking_params = (collect(2:20)[1:2:end], 10^(-10), SimpleChangePt(100))
```
The first defines the blocking updating scheme (in the future there might be a
larger choice). The second line places the knots on
`[2,4,6,8,10,12,14,16,18,20]`. Splitting into appropriate subsets is done
internally. `10^(-10)` is an artificial noise parameter that needs to be added
for the numerical purposes. Ideally we want this to be as small as possible,
however the algorithm may have problems with dealing with very small values. The
last arguments aims to remedy this. `SimpleChangePt(100)` has two functions.
One, it is a flag to the `mcmc` sampler that two sets of ODE solvers need to be
employed: for the segment directly adjacent to a knot from the left ODE solvers
for `M⁺`, `L`, `μ` are employed and `H`, `Hν` and `c` are computed as a
by-product. On the remaining part of blocks, the ODE solvers for `H`, `Hν` and
`c` are used directly. The second function of `SimpleChangePt()` is to indicate
the point at which a change needs to be made between these two solvers (which
for the example above is set to `100`). The reason for this functionality is
that solvers for `M⁺`, `L`, `μ` are more tolerant to very small values of the
artificial noise.

To define an MCMC sampler with no blocking nothing needs to be done (it's a
default). Alternatively, one can call
```julia
set_blocking!()
```
It resets the blocking to none. To pass the blocking scheme defined above one
could call
```julia
set_blocking!(setup, blocking, blocking_params)
```
## ODE solvers
There are a few standard, Runge-Kutta type ODE solvers implemented for solving
the backward ODE systems defining `M⁺`, `L`, `μ` and `H`, `Hν` and `c`. These
are:
```@docs
Ralston3
RK4
Tsit5
Vern7
```
Additionally, the change point between solvers for `M⁺`, `L`, `μ` and `H`, `Hν`
and `c` can be set outside of blocking when setting the solvers. An example code
is as follows
```julia
set_solver!(setup, Vern7(), NoChangePt())
```
```@docs
set_solver!
```
## MCMC parameters
There are some additional parameters that need to be passed to an MCMC samplers.
These need to be passed to
```@docs
set_mcmc_params!
```
## Initialisation of internal containers
Once all the setting functions above have been run (with the only exception
`set_blocking!` being optional), i.e.
```julia
setup = MCMCSetup(...)
set_observations!(setup, ...)
set_imputation_grid(setup, ...)
set_transition_kernels!(setup, ...)
set_priors!(setup, ...)
set_mcmc_params!(setup, ...)
set_solver!(setup, ...)
set_blocking(setup, ...) # optionally
```
then the following function should be run
```@docs
initialise!
```
Once run, the setup is complete and it is possible to commence the MCMC sampler. 
