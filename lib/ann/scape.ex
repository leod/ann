defmodule Scape do
  def create(organism_pid) do
    spawn(Scape, :start, [organism_pid])
  end

  def start(organism_pid) do
    receive do
      {^organism_pid, _name} ->
        xor_sim(organism_pid)
    end
  end

  def xor_sim(organism_pid) do
    # Expected values for XOR
    xor_list = [{[-1, -1], [-1]},
                {[1, -1], [1]},
                {[-1, 1], [1]},
                {[1, 1], [-1]}]

    xor_sim(organism_pid, xor_list, xor_list, 0)
  end

  def xor_sim(organism_pid, [{input, correct_output} | xor_list], all_xor_list, acc_err) do
    receive do
      # Input requested from sensor
      {from, :sense} ->
        #IO.puts "SCAPE SENSE #{inspect input}"
        from <- {self(), :input, input}
        xor_sim(organism_pid, [{input, correct_output} | xor_list], all_xor_list, acc_err)

      # Output given from actuator, compare to correct output
      {from, :act, output} ->
        #IO.puts "SCAPE ACT #{inspect output}"
        err = list_compare(output, correct_output)

        case xor_list do
          [] ->
            fitness = 1 / (acc_err + err + 0.00001)
            from <- {self, fitness, 1}
            xor_sim(organism_pid, all_xor_list, all_xor_list, 0)

          _ ->
            from <- {self, 0, 0}
            xor_sim(organism_pid, xor_list, all_xor_list, acc_err + err)
        end

      {^organism_pid, :terminate} ->
        :ok
    end
  end

  defp list_compare(a, b)
  when length(a) == length(b) do
    Enum.zip(a, b)
    |> Enum.reduce(0, fn {x, y}, e -> e + :math.pow(x - y, 2) end)
    #|> :math.sqrt()
  end
end
