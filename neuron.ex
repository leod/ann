defmodule Neuron do
  import Enum

  defrecord State, id: nil, organism_pid: nil, monitor_pid: nil, af: nil, w_input_pids: nil, output_pids: nil

  def create(organism_pid) do
    pid = spawn(Neuron, :start, [organism_pid])
  end

  def start(organism_pid) do
    IO.puts "Neuron begin #{inspect self}"

    receive do
      {^organism_pid, {id, monitor_pid, af, w_input_pids, output_pids}} ->
        loop(State.new(id: id,
                       organism_pid: organism_pid,
                       monitor_pid: monitor_pid,
                       af: af,
                       w_input_pids: w_input_pids,
                       output_pids: output_pids),
             w_input_pids, 0)
    end
  end

  def loop(s, [{:bias, bias}], acc) do
    #output = Neuron.af(acc + bias)
    output = case s.af do
      :tanh -> tanh(acc + bias)
    end
    map s.output_pids, fn pid ->
      pid <- {self, :forward, [output]}
    end

    loop(s, s.w_input_pids, 0)
  end

  def loop(s, [{input_pid, weights} | w_input_pids], acc) do
    monitor_pid = s.monitor_pid

    receive do
      {^input_pid, :forward, input} ->
        result = dot(input, weights)
        loop(s, w_input_pids, acc + result)

      {^monitor_pid, :get_state} ->
        monitor_pid <- {self, s.id, s.w_input_pids}

      {^monitor_pid, :terminate} ->
        :ok
    end
  end

  def tanh(x), do: :math.tanh(x)

  def dot(a, b), do: zip(a, b) |> reduce(0, fn {x, y}, acc -> acc + x * y end)
end
