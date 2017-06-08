require Logger

defmodule Blockchain.P2P.Server do
  alias Blockchain.P2P.{Clients, Command}

  # Servers
  def accept(port) do
    # The options below mean:
    #
    # 1. `:binary` - receives data as binaries (instead of lists)
    # 2. `packet: :line` - receives data line by line
    # 3. `active: false` - blocks on `:gen_tcp.recv/2` until data is available
    # 4. `reuseaddr: true` - allows us to reuse the address if the listener crashes
    #
    {:ok, socket} = :gen_tcp.listen(port,
                      [:binary, packet: :line, active: false, reuseaddr: true])
    Logger.info fn -> "Accepting connections on port #{port}" end
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.Supervisor.start_child(Blockchain.P2P.Server.TaskSupervisor, fn -> serve(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    Clients.add(client)
    loop_acceptor(socket)
  end

  defp serve(socket) do
    msg =
      with {:ok, data} <- read_line(socket),
           {:ok, command} <- Command.parse(data),
           do: Command.run(command)

    write_line(socket, msg)
    serve(socket)
  end

  defp read_line(socket) do
    :gen_tcp.recv(socket, 0)
  end

  defp write_line(socket, {:ok, text}) do
    :gen_tcp.send(socket, text)
  end

  defp write_line(socket, {:error, :unknown_type}) do
    :gen_tcp.send(socket, "unknown type\n")
  end

  # The connection was closed, exit politely.
  defp write_line(socket, {:error, :closed}), do: socket_died(socket, :shutdown)

  # Unknown error. Write to the client and exit.
  defp write_line(socket, {:error, error}), do: socket_died(socket, error)

  defp socket_died(socket, exit_status) do
    Clients.remove(socket)
    exit(exit_status)
  end

  def broadcast(data) do
    for c <- Clients.get_all() do
      case write_line(c, {:ok, data}) do
        {:error, _} ->
          # client is not reachable, forget it
          Clients.remove(c)
        _ ->
          :ok
      end
    end
  end
end