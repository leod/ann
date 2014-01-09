defmodule Neuron do
  def afs(), do:
    [:tanh, :cos, :sin, :sgn, :bin, :trinary, :linear]

  import Enum

  def delta_multiplier, do: :math.pi() * 2
  def sat_limit, do: :math.pi() * 2

  defrecord State, id: nil, organism_pid: nil, monitor_pid: nil, af: nil,
                   w_input_pids: nil, output_pids: nil,
                   w_input_pids_backup: nil, ro_pids: nil

  def start(organism_pid) do
    pid = spawn(Neuron, :init, [organism_pid])
  end

  def init(organism_pid) do
    ##IO.puts "Neuron begin #{inspect self}"

    {a, b, c} = :erlang.now()
    :random.seed(a, b, c)

    receive do
      {^organism_pid,
       {id, monitor_pid, af, w_input_pids, output_pids, ro_pids}} ->
        {self, :forward, [0]} |> send(ro_pids)         

        loop(State.new(id: id,
                       organism_pid: organism_pid,
                       monitor_pid: monitor_pid,
                       af: af,
                       w_input_pids: w_input_pids,
                       output_pids: output_pids,
                       ro_pids: ro_pids),
             w_input_pids, 0)
    end
  end

  def loop(s, [], acc) do
    output = apply(Neuron, s.af, [acc])
    {self, :forward, [output]} |> send(s.output_pids)

    #IO.puts "Neuron #{inspect s.id} forwarding to #{inspect s.output_pids}"
    loop(s, s.w_input_pids, 0)
  end

  def loop(s, [{:bias, bias}], acc) do
    loop(s, [], acc + bias)
  end

  def loop(s, [{input_pid, weights} | w_input_pids], acc) do
    monitor_pid = s.monitor_pid
    organism_pid = s.organism_pid

    #IO.puts "Neuron #{inspect s.id} waiting"
    #:timer.sleep(500)

    receive do
      {^input_pid, :forward, input} ->
        #IO.puts "Neuron #{inspect self} #{inspect s.id} got input #{inspect input} with weights #{inspect weights}"
        result = dot(input, weights)
        loop(s, w_input_pids, acc + result)

      {^organism_pid, :weights_backup} ->
        #IO.puts "Neuron #{inspect self} backup"
        loop(s.w_input_pids_backup(s.w_input_pids),
             [{input_pid, weights} | w_input_pids], acc)

      {^organism_pid, :weights_restore} ->
        #IO.puts "Neuron #{inspect self} restore"
        loop(s.w_input_pids(s.w_input_pids_backup), s.w_input_pids_backup, acc)

      {^organism_pid, :weights_perturb} ->
        #IO.puts "Neuron #{inspect self} perturb"
        new_w_input_pids = perturb_input(s.w_input_pids)
        loop(s.w_input_pids(new_w_input_pids), new_w_input_pids, acc)

      {from, :get_state} ->
        #IO.puts "Neuron #{inspect self} get_state"
        from <- {self, s.id, s.w_input_pids}
        loop(s, [{input_pid, weights} | w_input_pids], acc)

      {^organism_pid, :prepare_reactivate} ->
        #IO.puts "Neuron #{inspect self} prepare_reactivate"
        # Get rid of incoming messages from recurrent connections
        flush()
        organism_pid <- {self, :ready}
        receive do
          {^organism_pid, :reactivate} ->
            {self, :forward, [0]} |> send(s.ro_pids)
        end
        loop(s, s.w_input_pids, 0)

      {^monitor_pid, :terminate} ->
        #IO.puts "Neuron #{inspect self} terminate"
        :ok
    end
  end

  def dot(a, b) when length(a) == length(b) do
    zip(a, b) |> reduce(0, fn {x, y}, acc -> acc + x * y end)
  end

  def perturb_input(w_input_pids) do
    num_weights = :lists.sum(map(w_input_pids, fn
      {_, w} when is_list(w) -> length(w)
      _ -> 0
    end))
    p = 1 / :math.sqrt(num_weights)

    map w_input_pids, fn
      {:bias, bias} ->
        if :random.uniform() < p do
          {:bias, sat((:random.uniform() - 0.5) * delta_multiplier + bias,
                      -sat_limit, sat_limit)}
        else
          {:bias, bias}
        end

      {input_pid, weights} ->
        {input_pid, perturb_weights(weights, p)}
    end
  end

  def perturb_weights(weights, p) do
    map weights, fn w ->
      if :random.uniform() < p do
        sat((:random.uniform() - 0.5) * delta_multiplier + w,
            -sat_limit, sat_limit)
      else
        w
      end
    end
  end

  def sat(x, min, max) do
    cond do
      x < min -> min
      x > max -> max
      true -> x
    end
  end

  def send(message, pids) do
    map pids, fn pid -> pid <- message end
  end

  def flush() do
    receive do
      _ -> flush()
    after 0 -> :ok
    end
  end

  # Activation functions
  def tanh(x), do: :math.tanh(x)
  def cos(x), do: :math.cos(x)
  def sin(x), do: :math.sin(x)

  def sgn(x) when x > 0, do: 1
  def sgn(x), do: -1

  def bin(x) when x > 0, do: 1
  def bin(x), do: 0
  def trinary(x) when x < 0.33 and x > -0.33, do: 0
  def trinary(x) when x >= 0.33, do: 1
  def trinary(x) when x <= -0.33, do: -1
  def abs(x), do: :erlang.abs(x)
  def linear(x), do: x
  def quadratic(x) do
    sgn(x) * x * x
  end
  def sqrt(x), do: sgn(x) * :math.sqrt(Neuron.abs(x))
end
