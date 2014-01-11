defmodule GenotypeTest do
  use ExUnit.Case

  test "spawnable" do
    constraint = Genotype.Constraint.new(morphology: :img_mimic,
                                         neural_afs: [:tanh])
    
    Enum.map 1..100, fn _ ->
      organism_id = {Genotype.Organism, Genotype.generate_id()}
      IO.inspect organism_id

      Database.transaction fn ->
        Genotype.generate(organism_id, {Genotype.Species, :test}, constraint)
        |> Database.write
      end

      :erlang.process_flag(:trap_exit, true)
      pid = Organism.start_link(organism_id, nil, :test)

      receive do
        {:EXIT, pid, :normal} -> :ok
        {:EXIT, pid, err} -> throw err
      end
      
      Database.transaction fn -> 
        Database.delete_organism(organism_id)
      end
    end 
  end
end
