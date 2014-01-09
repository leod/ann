defmodule Platform do
  use GenServer.Behaviour

  defrecord State, active_modules: [], active_scapes: []
  defrecord ScapeInfo, address: nil, type: nil, parameters: nil

  def start(), do: start({[], []})
  
  def start(init_state)do
    case Process.whereis(:platform) do
      nil ->
        :gen_server.start(Platform, init_state, [])
      pid ->
        IO.puts "Platform #{inspect pid} already running"
    end
  end

  def init({modules, public_scapes}) do
    :erlang.process_flag(:trap_exit, true)
    Process.register(self, :platform)

    {a, b, c} = :erlang.now()
    :random.seed(a, b, c)
    
    Database.start
    start_modules(modules)

    active_scapes = start_scapes(public_scapes)

    IO.puts "Platform online"

    init_state = {modules, active_scapes}
    {:ok, init_state}
  end

  def start_modules(modules) do
    Enum.map modules, fn module -> apply(module, :start, []) end
  end

  def stop_modules(modules) do
    Enum.map modules, fn module -> apply(module, :stop, []) end
  end

  def start_scapes(scapes) do
    Enum.map scapes, fn scape ->
      pid = Scape.start_link({self, scape.type, scape.parameters})
      scape.pid pid
    end
  end

  def stop_scapes(scapes) do
    Enum.map scapes, fn scape ->
      :gen_server.cast(scape.pid, {self, :stop, :normal})
    end
  end

  def handle_call({:get_scape, type}, {monitor_pid, _ref}, s) do
    pid = case List.keyfind(s.active_scapes, type, 3) do
      false -> nil
      scape -> scape.pid
    end

    {:reply, pid, s}
  end

  def handle_call({:stop, :normal}, _, s) do
    {:stop, :normal, s}
  end

  def handle_call({:stop, :shutdown}, _, s) do
    {:stop, :shutdown, s}
  end

  def handle_cast({:init, init_state}, _) do
    {:noreply, init_state}
  end

  def handle_cast({:stop, :normal}, _, s) do
    {:stop, :normal, s}
  end

  def handle_cast({:stop, :shutdown}, _, s) do
    {:stop, :shutdown, s}
  end
end
