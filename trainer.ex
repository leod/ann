defmodule Trainer do
  def default_fitness_target, do: :inf
  def default_max_attempts, do: 20
  def default_max_evals, do: :inf

  def create(morphology, hidden_layer_densities) do
    create(morphology, hidden_layer_densities, default_fitness_target,
           default_max_attempts, default_max_evals)
  end

  def create(morphology, hidden_layer_densities, fitness_target,
             max_attempts, max_evals) do
    pid = spawn(Trainer, :loop,
                [morphology, hidden_layer_densities, fitness_target,
                 {1, max_attempts}, {0, max_evals}, {0, :best},
                 :experimental])
    Process.register(pid, :trainer)
  end

  def loop(morphology, _, fitness_target,
           {num_attempts, max_attempts}, {num_evals, max_evals},
           {best_fitness, best_genotype}, exp_genotype)
  when num_attempts >= max_attempts or
       num_evals >= max_evals or
       best_fitness >= fitness_target do
    Genotype.print(best_genotype)

   # genotype = Genotype.load(best_genotype)
   # [monitor] = Enum.filter(:ets.tab2list(genotype), fn o ->
   #   case o.id do
   #     {:monitor, _} -> true
   #     _ ->  false
   #   end
   # end)
   # a = Genotype.read(genotype, Enum.first(monitor.actuator_ids))
   # a = a.f :pts
   # Genotype.write(genotype, a)
   # Genotype.save(genotype, :out)
   # Organism.map(:out)

    IO.puts "Morphology #{morphology}, best fitness #{best_fitness}, num evals #{num_evals}"
  end

  def loop(morphology, hidden_layer_density, fitness_target,
           {num_attempts, max_attempts}, {num_evals, max_evals},
           {best_fitness, best_genotype}, exp_genotype) do
    Genotype.create(morphology, hidden_layer_density)
    |> Genotype.save(exp_genotype)

    organism_pid = Organism.map(exp_genotype)

    receive do
      {^organism_pid, fitness, evals, cycles, time} ->
        if fitness > best_fitness do
          :file.rename(exp_genotype, best_genotype)
          IO.puts "TRAINER: Keeping!"
          loop(morphology, hidden_layer_density, fitness_target,
               {1, max_attempts}, {num_evals + evals, max_evals},
               {fitness, best_genotype}, exp_genotype)
        else
          IO.puts "TRAINER: Throwing away!"
          loop(morphology, hidden_layer_density, fitness_target,
               {num_attempts + 1, max_attempts}, {num_evals + evals, max_evals},
               {best_fitness, best_genotype}, exp_genotype)
        end

      :terminate ->
        IO.puts "Trainer terminated"
        Genotype.print(best_genotype)

        IO.puts "Morphology #{morphology}, best fitness #{best_fitness}, num evals #{num_evals}"
    end
  end
end
