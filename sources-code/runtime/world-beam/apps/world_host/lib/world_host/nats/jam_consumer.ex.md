---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/nats/jam_consumer.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.324155+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/nats/jam_consumer.ex

```ex
defmodule WorldHost.Nats.JamConsumer do
  @moduledoc """
  Durable pull consumer for the `jam` JetStream stream.

  Subscribes to `jam.>` and fans committed cells out through Phoenix.PubSub
  so that any JamChannel subscriber can receive them:

      Phoenix.PubSub.broadcast(WorldHost.PubSub, "jam:" <> room_id, {:nats_cell, cell})

  This is used primarily for replay on late-join: when a new client joins
  `jam:<room_id>`, the JamChannel fetches the last N cells from the NATS
  consumer.

  Consumer naming: `world_host_jam` (durable, so it persists across restarts
  and picks up from where it left off).
  """

  use GenServer
  require Logger

  @consumer_name "world_host_jam"
  @stream        "jam"
  # How many messages to fetch per pull batch
  @batch         50

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ── Replay API ─────────────────────────────────────────────────────────────

  @doc """
  Fetch up to `limit` most-recent cells for a given room from JetStream.
  Returns a list of decoded cell maps (oldest first).
  """
  def recent_cells(room_id, limit \\ 50) do
    GenServer.call(__MODULE__, {:recent_cells, room_id, limit}, 10_000)
  end

  # ── GenServer ──────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %{}, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    case ensure_consumer() do
      :ok ->
        schedule_pull()
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("JamConsumer: consumer setup failed: #{inspect(reason)}; retrying in 5s")
        Process.send_after(self(), :retry_subscribe, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:retry_subscribe, state) do
    {:noreply, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_info(:pull, state) do
    pull_and_broadcast()
    schedule_pull()
    {:noreply, state}
  end

  @impl true
  def handle_call({:recent_cells, room_id, limit}, _from, state) do
    cells = fetch_recent(room_id, limit)
    {:reply, cells, state}
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp ensure_consumer do
    # NATS v2.10: DURABLE.CREATE requires the new CreateConsumerRequest wrapper
    # body = {"stream_name": "<stream>", "config": ConsumerConfig}
    config = %{
      "durable_name" => @consumer_name,
      "filter_subject" => "jam.>",
      "ack_policy" => "explicit",
      "deliver_policy" => "all",
      "max_deliver" => 3,
    }

    msg = Jason.encode!(%{"stream_name" => @stream, "config" => config})

    case Gnat.request(WorldHost.Nats.Conn,
           "$JS.API.CONSUMER.DURABLE.CREATE.#{@stream}.#{@consumer_name}", msg,
           receive_timeout: 5_000) do
      {:ok, %{body: body}} ->
        case Jason.decode!(body) do
          %{"error" => %{"err_code" => 10058}} -> :ok  # consumer already exists
          %{"error" => err} -> {:error, err}
          _ -> :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp pull_and_broadcast do
    req = Jason.encode!(%{"batch" => @batch, "expires" => 2_000_000_000})

    case Gnat.request(WorldHost.Nats.Conn,
           "$JS.API.CONSUMER.MSG.NEXT.#{@stream}.#{@consumer_name}", req,
           receive_timeout: 3_000) do
      {:ok, %{body: body, headers: headers}} ->
        ack_reply = get_header(headers, "Nats-Subject")
        process_message(body, ack_reply)

      {:error, :timeout} ->
        :ok

      {:error, reason} ->
        Logger.debug("JamConsumer pull: #{inspect(reason)}")
    end
  end

  defp process_message(body, ack_reply) do
    with {:ok, cell} <- Jason.decode(body),
         room_id when is_binary(room_id) <- extract_room_id(cell) do

      Phoenix.PubSub.broadcast(WorldHost.PubSub, "jam:#{room_id}", {:nats_cell, cell})

      if ack_reply do
        Gnat.pub(WorldHost.Nats.Conn, ack_reply, "")
      end
    end
  end

  defp fetch_recent(room_id, limit) do
    # Ephemeral ordered consumer filtered to room's subject, fetch last `limit`
    consumer_config = %{
      "filter_subject" => "jam.#{room_id}.cell",
      "deliver_policy" => "last_per_subject",
      "ack_policy" => "none",
      "num_replicas" => 1,
    }

    msg = Jason.encode!(%{"config" => consumer_config})
    inbox = "_INBOX.wh.#{:erlang.unique_integer([:positive])}"

    # Create ephemeral consumer and collect messages
    case Gnat.request(WorldHost.Nats.Conn,
           "$JS.API.CONSUMER.CREATE.#{@stream}", msg,
           receive_timeout: 3_000) do
      {:ok, %{body: body}} ->
        case Jason.decode!(body) do
          %{"name" => cname} ->
            cells = pull_batch(@stream, cname, inbox, limit)
            # Clean up ephemeral consumer
            Gnat.request(WorldHost.Nats.Conn,
              "$JS.API.CONSUMER.DELETE.#{@stream}.#{cname}", "",
              receive_timeout: 2_000)
            cells

          _ -> []
        end

      _ -> []
    end
  end

  defp pull_batch(stream, consumer, _inbox, limit) do
    req = Jason.encode!(%{"batch" => limit, "expires" => 2_000_000_000})

    case Gnat.request(WorldHost.Nats.Conn,
           "$JS.API.CONSUMER.MSG.NEXT.#{stream}.#{consumer}", req,
           receive_timeout: 3_000) do
      {:ok, %{body: body}} ->
        case Jason.decode(body) do
          {:ok, cell} when is_map(cell) -> [cell]
          _ -> []
        end

      _ -> []
    end
  end

  defp extract_room_id(%{"room_id" => r}), do: r
  defp extract_room_id(%{"room" => r}), do: r
  defp extract_room_id(_), do: nil

  defp get_header(headers, name) when is_list(headers) do
    case List.keyfind(headers, name, 0) do
      {_, v} -> v
      nil -> nil
    end
  end
  defp get_header(_, _), do: nil

  defp schedule_pull, do: Process.send_after(self(), :pull, 100)
end

```
