defmodule Neuron do
  import Enum

  def create(mapper_pid) do
    pid = spawn(Neuron, :loop, [mapper_pid])
  end

  def loop(mapper_pid) do
    IO.puts "Neuron begin #{inspect self}"

    receive do
      {^mapper_pid, {id, monitor_pid, af, w_input_pids, output_pids}} ->
        loop(id, monitor_pid, af, w_input_pids,
             w_input_pids, output_pids, 0)
    end
  end

  def loop(id, mapper_pid, af, [{:bias, bias}],
            all_w_input_pids, output_pids, acc) do
    #output = Neuron.af(acc + bias)
    output = case af do
      :tanh -> tanh(acc + bias)
    end
    map output_pids, fn pid ->
      pid <- {self, :forward, [output]}
    end

    loop(id, mapper_pid, af, all_w_input_pids,
         all_w_input_pids, output_pids, 0)
  end

  def loop(id, monitor_pid, af, [{input_pid, weights} | w_input_pids],
            all_w_input_pids, output_pids, acc) do
    receive do
      {^input_pid, :forward, input} ->
        result = dot(input, weights)
        loop(id, monitor_pid, af, w_input_pids,
             all_w_input_pids, output_pids, acc + result)

      {^monitor_pid, :get_state} ->
        monitor_pid <- {self, id, all_w_input_pids}

      {^monitor_pid, :terminate} ->
        :ok
    end
  end

  def tanh(x), do: :math.tanh(x)

  def dot(a, b), do: zip(a, b) |> reduce(0, fn {x, y}, acc -> acc + x * y end)
end
