defmodule MutationsTest do
  use ExUnit.Case

  test "spawnable" do
    constraint = Genotype.Constraint.new(morphology: :img_mimic,
                                         neural_afs: [:tanh])
    
    Enum.map 1..1000, fn _ ->
      organism_id = {Genotype.Organism, Genotype.generate_id()}

      Database.transaction fn ->
        Genotype.generate(organism_id, {Genotype.Species, :test}, constraint)
        |> Database.write
      end

      :erlang.process_flag(:trap_exit, true)

      Enum.map 1..500, fn _ ->
        Mutations.mutate(organism_id)
        pid = Organism.start_link(organism_id, nil, :test)

        receive do
          {:EXIT, ^pid, :normal} -> :ok
          {:EXIT, ^pid, err} -> throw err
        end
      end

      Database.transaction fn -> 
        Database.delete_organism(organism_id)
      end
    end 
  end
end
