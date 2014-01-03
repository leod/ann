defmodule Population.Competition do
  import Enum

  # Competition is an algorithm for generating a new generation of organisms
  # out of the current one.
  def competition(sorted_summaries, population_limit, neural_energy_cost) do
    {alotments, next_generation_size_est} =
      calculate_alotments(sorted_summaries, neural_energy_cost)
    normalizer = next_generation_size_est / population_limit

    IO.puts "Competition: Estimated next generation size #{next_generation_size_est}"
    IO.puts "Competition: Normalizer #{normalizer}"

    gather_survivors(alotments, normalizer)
  end  

  # Calculates for every organism the allowed number of offspring
  # based on the organisms' fitness and number of neurons.
  # Returns the list of alotments and the new population size
  defp calculate_alotments(sorted_summaries, neural_energy_cost) do
    map_reduce sorted_summaries, 0,
    fn {fitness, num_neurons, organism_id}, population_size ->
      neural_alotment = fitness / neural_energy_cost
      offspring_alotment = neural_alotment / num_neurons

      {{offspring_alotment, fitness, num_neurons, organism_id},
       population_size + offspring_alotment}
    end
  end

  # Produes offspring for those organisms deserving it based on their alotment
  def gather_survivors(alotments, normalizer) do
    map(alotments, fn {alotment, fitness, num_neurons, organism_id} ->
      normalized_alotment = :erlang.round(alotment / normalizer)
      #IO.puts "Organism id #{inspect organism_id} producing #{normalized_alotment} offspring"

      if normalized_alotment >= 1 do
        offspring_ids = if normalized_alotment >= 2 do
          map 1..normalized_alotment-1, fn _ ->
              create_offspring(organism_id)
          end
        else
          []
        end
        #IO.puts "-> #{length([organism_id | offspring_ids])}"

        [organism_id | offspring_ids]
      else
        #IO.puts "Deleting organism #{inspect organism_id}"
        #Database.delete_organism(organism_id)

        []
      end
    end)
    |> concat
  end

  # Clones an organism and then mutates it.  Note that at this point,
  # the organism id still needs to be added to its species
  def create_offspring(organism_id) do
    id = Database.clone_organism(organism_id)
    Mutations.mutate(id)
    id
  end
end
