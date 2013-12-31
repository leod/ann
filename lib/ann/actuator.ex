defmodule Actuator do
  defrecord State, id: nil, monitor_pid: nil, organism_pid: nil, f: nil,
                   scape: nil, input_pids: nil, trace: false

  def create(organism_pid) do
    spawn(Actuator, :start, [organism_pid])
  end

  def start(organism_pid) do
    #IO.puts "Actuator begin #{inspect self}"

    receive do
      {^organism_pid, {id, monitor_pid, f, scape, input_pids}} ->
        loop(State.new(id: id,
                       monitor_pid: monitor_pid,
                       organism_pid: organism_pid,
                       f: f,
                       scape: scape,
                       input_pids: input_pids),
             input_pids, [])
    end
  end

  def loop(s, [input_pid | input_pids], acc) do
    monitor_pid = s.monitor_pid
    organism_pid = s.organism_pid

    receive do
      {^organism_pid, :enable_trace} ->
        IO.puts "yo"
        loop(s.trace(true), [input_pid | input_pids], acc)

      {^input_pid, :forward, input} ->
        loop(s, input_pids, :lists.append(input, acc))

      {^monitor_pid, :terminate} ->
        :ok
    end
  end

  def loop(s, [], acc) do
    #IO.inspect s.scape
    #IO.inspect s.f
    #IO.inspect acc
    {fitness, halt_flag} = apply(Actuator, s.f, [Enum.reverse(acc), s.scape])

    if s.trace do
      IO.puts "Actuator #{inspect self}: #{inspect acc} -> #{fitness}, #{halt_flag}"
    end

    #:timer.sleep(1000)
    s.monitor_pid <- {self, :sync, fitness, halt_flag}
    loop(s, s.input_pids, [])
  end

  def pts(output, _) do
    :io.format("Actuator result: ~p~n", [output])
    {0, 0}
  end

  def xor_send_output(output, scape) do
    scape <- {self, :act, output}
    receive do
      {scape, fitness, halt_flag} ->
        {fitness, halt_flag}
    end
  end
end