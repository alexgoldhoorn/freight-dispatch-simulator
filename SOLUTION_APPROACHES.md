# Model and solution approaches

## 1. The problem

A fleet of vehicles serves transport orders (freights) over a day or a week.

- **Freight** *i*: weight *w<sub>i</sub>*, pickup and delivery coordinates, a
  **release time** *r<sub>i</sub>* (CSV `pickup_time`: the order becomes known and
  can be dispatched) and a **deadline** *d<sub>i</sub>* (CSV `delivery_time`).
- **Vehicle** *j*: capacity *Q<sub>j</sub>*, constant speed, a start location
  (where it is at *t* = 0) and a base (defaults to the start).

Distances are great-circle distances (haversine). Travel time = distance / speed.

## 2. Execution rules

The same rules are used by the simulation, the analytic evaluator, the local
search and the MILP. This is what makes the numbers comparable.

1. **One freight per trip.** A trip goes current location → pickup → delivery → base.
   The first trip of a vehicle starts from its start location, later trips from its base.
2. **Capacity is per trip:** vehicle *j* can carry freight *i* iff *w<sub>i</sub>* ≤ *Q<sub>j</sub>*.
3. **Online dispatch at release.** At *r<sub>i</sub>* the dispatcher assigns freight *i*
   to a vehicle. A busy vehicle can be chosen: the freight waits in that vehicle's queue.
4. **FIFO per vehicle.** Each vehicle executes its freights in release order. A trip
   starts at max(*r<sub>i</sub>*, time the vehicle is back at base).
5. **Unserved** only when no vehicle can carry the weight.
6. **Lateness** *L<sub>i</sub>* = max(0, delivery time − *d<sub>i</sub>*). Late deliveries are allowed but penalised.

### Objective

All methods are scored by one objective (weights in `ObjectiveWeights`):

```
objective = total km + 100 × total lateness (hours) + 10 000 × unserved freights
```

Other reported KPIs: freights on time, makespan (time the last vehicle is back at
base) and utilization (busy time / makespan, always in [0, 1]).

### Simplifications (known, deliberate)

- No consolidation: a vehicle carries one freight at a time (full truckload).
- Vehicles return to base after every trip.
- No road network, traffic, driver hours or service times.
- Deterministic travel times.

## 3. Discrete-event simulation

`simulate(instance, strategy)` runs a [ConcurrentSim.jl](https://github.com/JuliaDynamics/ConcurrentSim.jl)
simulation. A dispatcher process wakes up at every release time and asks the
strategy for a vehicle. Each vehicle is a process with a FIFO inbox that performs
the trips as timed events. The results tables are built from what the vehicle
processes actually did, not from what the dispatcher planned.

`evaluate_assignment(instance, assignment)` replays any fixed assignment
(freight → vehicle) through this same simulation. That is how local search and
MILP results are measured.

`evaluate_plan` computes the same KPIs analytically in O(n). It is used inside
the local search. The tests check that it matches the simulation exactly on random
assignments.

## 4. Greedy online rules

Decide at release time using only what is known then. Ties go to the first vehicle
in input order, so runs are deterministic.

| Rule | Choice among vehicles that can carry the freight |
|---|---|
| **FCFS** | first idle vehicle; if all busy, the one free first |
| **Cost** | idle vehicle nearest to the pickup (fewest empty km); if all busy, the one free first |
| **Distance** | idle vehicle with the shortest full trip; if all busy, the one free first |
| **OverallCost** | earliest estimated delivery time, counting queueing (idle and busy vehicles compete) |

The rules take microseconds per decision and need no future information, but they
are myopic. On the included datasets the best rule is 0–53 % above the best
objective found (see [docs/BENCHMARK.md](docs/BENCHMARK.md)).

## 5. Local search

`local_search_optimize` starts from a greedy assignment and applies the first
improving move until none is left:

- **relocate**: move one freight to another vehicle that can carry it;
- **swap**: exchange the vehicles of two freights.

Moves are scored with the analytic evaluator, which makes a full evaluation
cheap. The result is a local optimum, with no optimality guarantee. It needs all
freights up front (offline/batch), which the greedy rules do not.

Natural extensions: simulated annealing or tabu search to escape local optima,
and moves that change the order within a vehicle (this requires relaxing the FIFO rule).

## 6. MILP

`optimize_dispatch` solves the assignment exactly under the rules of section 2
with [JuMP](https://jump.dev) + [HiGHS](https://highs.dev). Because the order on
each vehicle is fixed (release order), sequencing reduces to precedence
constraints between pairs of freights on the same vehicle.

Index *i* < *k* means *i* is released before *k*. Only pairs (*i*, *j*) with
*w<sub>i</sub>* ≤ *Q<sub>j</sub>* get variables.

| Symbol | Meaning |
|---|---|
| *x<sub>ij</sub>* ∈ {0,1} | freight *i* served by vehicle *j* |
| *y<sub>ij</sub>* ∈ {0,1} | *i* is the first trip of *j* (only for vehicles whose start ≠ base) |
| *S<sub>i</sub>* ≥ *r<sub>i</sub>* | trip start time |
| *L<sub>i</sub>* ≥ 0 | lateness in seconds |
| *c<sub>ij</sub>*, *T<sub>ij</sub>*, *D<sub>ij</sub>* | trip km, trip duration, time until delivery when leaving from the base |
| *c'<sub>ij</sub>*, *T'<sub>ij</sub>*, *D'<sub>ij</sub>* | the same when leaving from the start location |

```
min   Σ c_ij x_ij + Σ (c'_ij − c_ij) y_ij + (100 / 3600) Σ L_i

s.t.  Σ_j x_ij = 1                                        every freight some vehicle can carry
      y_ij ≤ x_ij
      y_ij ≥ x_ij − Σ_{k<i} x_kj                           first trip of j
      y_ij + x_kj ≤ 1                          ∀ k < i
      S_i ≥ S_k + T_kj + (T'_kj − T_kj) y_kj − M (2 − x_kj − x_ij)    ∀ k < i   (FIFO precedence)
      L_i ≥ S_i + D_ij + (D'_ij − D_ij) y_ij − d_i − M (1 − x_ij)
```

- The best greedy solution is passed as a MIP start, so there is always an incumbent.
- At the optimum, the model objective equals the objective measured by replaying the
  assignment in the simulation. The test suite checks this on every run.
- Size is O(n² m) constraints with big-M precedence, so the LP relaxation is weak. In
  practice optimality is proven for up to about 15–20 freights within a minute
  (see the scalability table in [docs/BENCHMARK.md](docs/BENCHMARK.md)). After the
  time limit, the best solution found and the remaining gap are returned.

## 7. Which approach when

| | Greedy | Local search | MILP |
|---|---|---|---|
| Information needed | only the past (online) | all freights (batch) | all freights (batch) |
| Time | µs per decision | ms | seconds to minutes |
| Quality guarantee | none | local optimum | proven optimum (or gap) |
| Scales to | thousands | hundreds | tens |

In practice they combine: greedy for real-time decisions, periodic re-optimisation
of the not-yet-started freights with local search or MILP (rolling horizon), and
the MILP as a yardstick to measure how far the fast methods are from optimal.

## References

- Toth & Vigo (eds.), *Vehicle Routing: Problems, Methods, and Applications*, 2nd ed., SIAM, 2014.
- Pillac, Gendreau, Guéret, Medaglia, "A review of dynamic vehicle routing problems", *EJOR* 225(1), 2013.
- Law, *Simulation Modeling and Analysis*, 5th ed., McGraw-Hill, 2015.
