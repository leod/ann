defmodule Population do
  use GenServer.Behaviour

  import Enum

  @init_species_size 100
  @species_size_limit 200
  @generation_limit 100
  @evaluations_limit :inf
  @fitness_goal :inf
  @survival_percentage 0.5
  @neural_efficiency 0.05
  
  defrecord State, op_mode: nil,
                   op_tag: nil,
                   population_id: nil,
                   cur_organisms: [],
                   organism_ids: [],
                   num_organisms: nil,
                   organisms_left: 0,
                   organism_summaries: [],
                   pop_generation: 0,

                   eval_acc: 0,
                   cycle_acc: 0,
                   time_acc: 0,
                   
                   step_size: nil,
                   next_step: nil,
                   goal_status: nil,
                   selection_algorithm: :competition

  def start_link(parameters // []), do:
    :gen_server.start_link(Population, parameters, []) 

  def start(parameters // []), do:
    :gen_server.start(Population, parameters, [])

  def init(pid, init_state), do:
    :gen_server.cast(pid, {:init, init_state})

  def init({op_mode, population_id, selection_algorithm}) do
    :erlang.process_flag(:trap_exit, true)
    Process.register(self, :population)

    organism_ids = get_organism_ids(population_id)
    cur_organisms = start_organisms(op_mode, organism_ids)

    state = State.new(op_mode: op_mode,
                      population_id: population_id,
                      cur_organisms: cur_organisms,
                      num_organisms: length(organism_ids),
                      organisms_left: length(organism_ids),
                      op_tag: :continue,
                      selection_algorithm: selection_algorithm)

    IO.puts "Population monitor started"
    {:ok, state}
  end

  def handle_call({:stop, :normal}, _, state) do
    lc {_, pid} inlist state.cur_organisms, do: pid <- {self, :terminate}
    {:stop, :normal, state}
  end

  def handle_cast({organism_id, :terminated, fitness,
                   eval_acc, cycle_acc, time_acc},
                  state=State[selection_algorithm: :competition]) do
    state = state.eval_acc(state.eval_acc + eval_acc)
                 .cycle_acc(state.cycle_acc + cycle_acc)
                 .time_acc(state.time_acc + time_acc)

    if state.organisms_left == 1 do
      mutate_population(state.population_id, @species_size_limit, :competition)
      new_pop_generation = state.pop_generation + 1

      IO.puts "Generation of population #{new_pop_generation} ended"

      case state.op_tag do
        :continue ->
          species_ids = Database.dirty_read(state.population_id).species_ids
          fit_list = lc species_id inlist species_ids,
                     do: Genotype.read(species_id).fitness
          best_fitness = lc {_, _, max_fitness, _} inlist fit_list,
                         do: max_fitness
                         |> Enum.sort |> Enum.reverse |> Enum.first

          if new_pop_generation >= @generation_limit or
             state.eval_acc >= @evaluations_limit or
             best_fitness >= @fitness_goal do
            organism_ids = get_organism_ids(state.population_id)
            state = state.organism_ids(organism_ids)
                         .num_organisms(length(organism_ids))
                         .organisms_left(length(organism_ids))
                         .pop_generation(new_pop_generation)
           
            {:stop, :normal, state}
          else
            organism_ids = get_organism_ids(state.population_id)
            cur_organisms = start_organisms(state.op_mode, organism_ids)

            state = state.cur_organisms(cur_organisms)
                         .num_organisms(length(organism_ids))
                         .organisms_left(length(organism_ids))
                         .pop_generation(new_pop_generation)
            {:noreply, state}
          end

        :done ->
          IO.puts "Shutting down population"
          
          state = state.organisms_left(0).pop_generation(new_pop_generation)
          {:stop, :normal, state}

        :pause ->
          IO.puts "Pausing population"

          state = state.organisms_left(0).pop_generation(new_pop_generation)
          {:noreply, state}
      end
    else
      cur_organisms = List.keydelete(state.cur_organisms, organism_id, 0)
      state = state.cur_organisms(cur_organisms)
                   .organisms_left(state.organisms_left - 1)
      {:noreply, state}
    end
  end

  def handle_cast({:op_tag, :pause}, state=State[op_tag: :continue]), do:
    {:noreply, state.op_tag(:pause)}

  def handle_cast({:op_tag, :continue}, state=State[op_tag: :pause]) do
    organism_ids = get_organism_ids(state.population_id)
    cur_organisms = start_organisms(state.op_mode, organism_ids)

    state = state.cur_organisms(cur_organisms)
                 .num_organisms(length(organism_ids))
                 .organisms_left(length(organism_ids))
                 .op_tag(:continue)
    {:noreply, state}
  end

  def get_organism_ids(population_id), do: get_organism_ids(population_id, :all)
  def get_organism_ids(population_id, :all) do
    Database.read(population_id).species_ids 
    |> Enum.map fn species_id -> Database.read(species_id).organism_ids end
    |> Enum.concat
  end
  def get_organism_ids(population_id, :champion) do
    Database.read(population_id).species_ids 
    |> Enum.map fn species_id -> Database.read(species_id).champion_ids end
    |> Enum.concat
  end

  def start_organisms(op_mode, organism_ids), do:
    Enum.map(organism_ids, fn id -> {id, Organism.start(id, self)} end)

  def init_population({population_id, species_constraints,
                       op_mode, selection_algorithm}) do
    :random.seed(:erlang.now())
    result = :mnesia.transaction fn ->
      if Genotype.try_read(population_id) != nil, do:
          Database.delete_population(population_id)
      create_population(population_id, species_constraints)
    end

    case result do
      {:atomic, _} ->
        start({op_mode, population_id, selection_algorithm})
      error ->
        IO.puts "Population: Error: #{inspect error}"
    end
  end

  def create_population(population_id, species_constraints) do
    species_size = @init_species_size
    species_ids = lc constraint inlist species_constraints,
                  do: create_species(population_id, constraint, :origin,
                                     species_size)
    Genotype.Population.new(id: population_id, species_ids: species_ids)
    |> Database.write
  end

  def create_species(population_id, constraint, fingerprint, species_size) do
    species_id = {Genotype.Species, Genotype.generate_id()}

    # Create organisms for species
    organism_ids = Enum.map 1..species_size, fn _ ->
      organism_id = {Genotype.Organism, Genotype.generate_id()}
      Genotype.generate(organism_id, species_id, constraint)
    end
    |> Database.write

    Genotype.Species.new(id: species_id,
                         population_id: population_id,
                         fingerprint: fingerprint,
                         constraint: constraint,
                         organism_ids: organism_ids) |> Database.write
    species_id 
  end

  def mutate_population(population_id, species_size_limit, algorithm) do
    neural_energy_cost = calculate_energy_cost(population_id)
    :mnesia.transaction fn ->
      population = Database.read(population_id)
      Enum.map population.species_ids &mutate_species(&1, species_size_limit,
                                                      neural_energy_cost, 
                                                      algorithm)
    end
  end

  def mutate_species(species_id, population_limit, neural_energy_cost,
                     algorithm) do
    species = Database.read(species_id)
    {avg_fitness, std_fitness, max_fitness, min_fitness}
      = calculate_species_fitness(species)
    summaries = get_organism_summaries(species.organism_ids)

    case algorithm do
      :competition ->
        num_survivors = round(length(summaries) * @survival_percentage)

        # Sort our organsims by their true fitness, which is the fitness
        # divided by a factor depending on the organism's number of neurons 
        sorted_summaries = summaries
          |> map(fn summary={fitness, num_neurons, _} ->
                    {fitness / :math.pow(num_neurons, @neural_efficiency),
                    summary}
                 end)
          |> sort
          |> reverse
          |> map(fn {_true_fitness, rest} -> rest end)

        valid_summaries = :list.sublist(sorted_summaries, num_survivors)
        invalid_summaries = sorted_summaries -- valid_summaries

        {_, _, invalid_organism_ids} = List.unzip(invalid_summaries)
        map invalid_organism_ids, &Database.delete_organism(&1)

        {_, _, champion_ids} = List.sublist(valid_summaries, 3)
                               |> List.unzip

        IO.puts "Population: valid summaries: #{inspect valid_summaries}"
        IO.puts "Population: invalid summaries: #{inspect invalid_summaries}"
        IO.puts "Population: neural energy cost: #{inspect neural_energy_cost}"

        new_organism_ids = Competition.competition(valid_summaries,
                                                   population_limit,
                                                   neural_energy_cost)

        {fitness_list, _, _} = List.unzip(sorted_summaries)
        [top_fitness | _] = fitness_list

        new_innovation_factor = if top_fitness > species.innovation_factor,
                                do: 0, else: species.innovation_factor - 1
        
        species.organism_ids(new_organism_ids)
               .champion_ids(champion_ids)
               .fitness({avg_fitness, std_fitness, max_fitness, min_fitness})
               .innovation_factor(new_innovation_factor)
        |> Database.write
    end


  end

  def get_organism_summaries(organism_ids) do
    Enum.map organism_ids, fn organism_id ->
      organism = Database.read(organism_id)
      monitor = Database.read(organism.monitor_id)

      {organism.fitness, length(monitor.neuron_ids), organism_id}
    end
  end

  def calculate_energy_cost(population_id) do
    organism_ids = get_organism_ids(population_id)
    total_energy = lc id inlist organism_ids, do: Database.read(id).fitness
                   |> :lists.sum
    total_neurons = lc id inlist organism_ids,
                    do: Database.read(Database.read(id).monitor_id).neuron_ids
                        |> length
                    |> :lists.sum
    total_energy / total_neurons
  end

  def calculate_species_fitness(species=Genotype.Species[]) do
    fitness_list = reduce species.organism_ids, [], fn organism_id, acc ->
      case Database.read(organism_id).fitness do
        nil -> acc
        fitness -> [fitness | acc]
      end
    end
    |> sort

    [min_fitness | _] = fitness_list
    [max_fitness | _] = reverse(fitness_list)
    avg_fitness = Stats.average(fitness_list)
    std_fitness = Stats.standard_deviation(fitness_list)

    {avg_fitness, std_fitness, max_fitness, min_fitness}
  end
end
