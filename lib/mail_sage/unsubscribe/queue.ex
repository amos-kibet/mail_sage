defmodule MailSage.Unsubscribe.Queue do
  @moduledoc """
  Manages the queue of unsubscribe jobs and ensures we don't overwhelm the system.
  """

  use GenServer

  alias MailSage.Unsubscribe.Metrics

  require Logger

  @max_concurrent_jobs 5
  @queue_check_interval 5 * 60

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def enqueue(email) do
    GenServer.cast(__MODULE__, {:enqueue, email})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    schedule_queue_check()

    {:ok,
     %{
       queue: :queue.new(),
       active_jobs: %{},
       metrics: %{
         total_processed: 0,
         current_queue_size: 0
       }
     }}
  end

  @impl true
  def handle_cast({:enqueue, email}, state) do
    new_state = %{state | queue: :queue.in(email, state.queue)}
    update_metrics(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:check_queue, state) do
    schedule_queue_check()
    new_state = process_queue(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.active_jobs, ref) do
      {nil, _} ->
        {:noreply, state}

      {email, active_jobs} ->
        Logger.warning("Unsubscribe job failed for email #{email.id}: #{inspect(reason)}")
        new_state = %{state | active_jobs: active_jobs}
        {:noreply, new_state}
    end
  end

  # Private Functions

  defp schedule_queue_check do
    Process.send_after(self(), :check_queue, @queue_check_interval)
  end

  defp process_queue(state) do
    if can_start_new_job?(state) do
      case :queue.out(state.queue) do
        {{:value, email}, new_queue} ->
          start_job(email, %{state | queue: new_queue})

        {:empty, _} ->
          state
      end
    else
      state
    end
  end

  defp can_start_new_job?(state) do
    map_size(state.active_jobs) < @max_concurrent_jobs
  end

  defp start_job(email, state) do
    case MailSage.Unsubscribe.Agent.start_link(email) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        new_active_jobs = Map.put(state.active_jobs, ref, email)
        new_state = %{state | active_jobs: new_active_jobs}
        update_metrics(new_state)
        new_state

      {:error, reason} ->
        Logger.error("Failed to start unsubscribe job for email #{email.id}: #{inspect(reason)}")
        state
    end
  end

  defp update_metrics(state) do
    Metrics.gauge(:queue_size, :queue.len(state.queue))
    Metrics.gauge(:active_jobs, map_size(state.active_jobs))
  end
end
