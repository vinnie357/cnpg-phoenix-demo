defmodule CnpgPhoenixDemoWeb.HomeLive do
  use CnpgPhoenixDemoWeb, :live_view

  alias CnpgPhoenixDemo.Analytics
  alias CnpgPhoenixDemo.Databases
  alias CnpgPhoenixDemo.Notes
  alias CnpgPhoenixDemo.Status

  @burst_size 20
  @burst_interval_ms 150

  @impl true
  def mount(_params, _session, socket) do
    analytics? = Analytics.configured?()

    # Live updates: every connected client subscribes, so a note or visit
    # written by ANY browser (or the simulator) is pushed to ALL of them.
    if connected?(socket) do
      :ok = Notes.subscribe()
      if analytics?, do: :ok = Analytics.subscribe()
    end

    # Record the visit in the second cluster — only once per page load
    # (connected mount) and only when analytics is wired up.
    if analytics? and connected?(socket) do
      {:ok, _visit} = Analytics.record_visit(Status.pod_name(), Status.node_name())
    end

    {:ok,
     socket
     |> assign(:page_title, "CNPG Phoenix Demo")
     |> assign(:version, Status.version())
     |> assign(:topology, Status.topology())
     |> assign(:replication, Status.replication())
     |> assign(:pod, Status.pod_name())
     |> assign(:node, Status.node_name())
     |> assign(:analytics?, analytics?)
     |> assign(:visits, if(analytics?, do: Analytics.stats()))
     |> assign(:burst_left, 0)
     |> assign(:databases, databases_with_tables())
     |> assign(:form, to_form(Notes.change_note()))
     |> assign(:notes, Notes.list_notes())}
  end

  @impl true
  def handle_event("save", %{"note" => params}, socket) do
    # The note list itself updates via the PubSub broadcast, same as
    # every other connected browser.
    case Notes.create_note(params) do
      {:ok, _note} ->
        {:noreply, assign(socket, :form, to_form(Notes.change_note()))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("simulate", _params, socket) do
    if socket.assigns.burst_left > 0 or not socket.assigns.analytics? do
      {:noreply, socket}
    else
      send(self(), :burst_tick)
      {:noreply, assign(socket, :burst_left, @burst_size)}
    end
  end

  @impl true
  def handle_info(:burst_tick, socket) do
    case socket.assigns.burst_left do
      0 ->
        {:noreply, socket}

      left ->
        {:ok, _visit} = Analytics.record_visit("simulated-traffic", Status.node_name())
        if left > 1, do: Process.send_after(self(), :burst_tick, @burst_interval_ms)
        {:noreply, assign(socket, :burst_left, left - 1)}
    end
  end

  def handle_info({:visit_recorded, _visit}, socket) do
    {:noreply, assign(socket, :visits, Analytics.stats())}
  end

  def handle_info({:note_created, _note}, socket) do
    {:noreply, assign(socket, :notes, Notes.list_notes())}
  end

  defp databases_with_tables do
    for {key, label, repo} <- Databases.browsable_databases() do
      %{key: key, label: label, tables: Databases.list_tables(repo)}
    end
  end

  defp pg_version_short(version) do
    case Regex.run(~r/^PostgreSQL (\S+)/, version) do
      [_, v] -> v
      _ -> version
    end
  end

  defp pg_platform(version) do
    case Regex.run(~r/on (\S+?),/, version) do
      [_, triple] -> triple |> String.split("-") |> hd()
      _ -> nil
    end
  end

  defp standby_count({:ok, standbys}), do: length(standbys)
  defp standby_count(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div>
        <h1 class="text-2xl font-semibold text-balance">CloudNativePG topology, live</h1>
        <p class="mt-1 text-sm opacity-70">
          Served by pod <span id="pod-name" class="font-mono">{@pod}</span>
          on node <span id="node-name" class="font-mono">{@node}</span>
          — every value below is read over this page's own database connections.
        </p>
      </div>

      <div class="stats stats-vertical sm:stats-horizontal w-full border border-base-300 bg-base-100">
        <div class="stat">
          <div class="stat-title">Postgres</div>
          <div class="stat-value text-2xl" title={@version}>{pg_version_short(@version)}</div>
          <div class="stat-desc">{pg_platform(@version) || "server version"}</div>
        </div>
        <div class="stat">
          <div class="stat-title">Connection pools</div>
          <div class="stat-value text-2xl tabular-nums">{length(@topology)}</div>
          <div class="stat-desc">write / read / analytics</div>
        </div>
        <div class="stat">
          <div class="stat-title">Streaming standbys</div>
          <div class="stat-value text-2xl tabular-nums">
            {standby_count(@replication) || "—"}
          </div>
          <div class="stat-desc">pg_stat_replication</div>
        </div>
        <div :if={@analytics?} class="stat">
          <div class="stat-title">Page visits</div>
          <div id="visit-count" class="stat-value text-2xl tabular-nums">{@visits.total}</div>
          <div class="stat-desc">stored in metrics-db</div>
        </div>
      </div>

      <section id="topology" class="card border border-base-300 bg-base-100">
        <div class="card-body gap-3">
          <h2 class="text-xs font-semibold uppercase tracking-wider opacity-60">
            Topology — where each pool landed
          </h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>pool</th>
                  <th>dialed</th>
                  <th>server</th>
                  <th>CNPG cluster</th>
                  <th>role</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={t <- @topology} id={"topo-#{t.role |> String.replace(~r/\W+/, "-")}"}>
                  <td class="font-medium whitespace-nowrap">{t.role}</td>
                  <td class="font-mono text-xs">{t.dialed}</td>
                  <td class="font-mono text-xs tabular-nums">{t.server}</td>
                  <td class="font-mono text-xs">{t.cluster_name || "—"}</td>
                  <td>
                    <%= case t.in_recovery do %>
                      <% true -> %>
                        <span class="badge badge-info badge-sm whitespace-nowrap">hot standby</span>
                      <% false -> %>
                        <span class="badge badge-success badge-sm">primary</span>
                      <% _ -> %>
                        <span class="badge badge-ghost badge-sm">unknown</span>
                    <% end %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div id="replication" class="flex flex-wrap items-center gap-2 text-sm">
            <%= case @replication do %>
              <% {:ok, []} -> %>
                <span class="opacity-60">No streaming standbys (single-instance cluster).</span>
              <% {:ok, standbys} -> %>
                <span class="opacity-60">Streaming standbys:</span>
                <span
                  :for={s <- standbys}
                  class="badge badge-outline gap-1 font-mono text-xs whitespace-nowrap"
                >
                  {s.name} <span class="opacity-60">{s.state}/{s.sync}</span>
                </span>
              <% {:error, :needs_grant} -> %>
                <span class="opacity-60">
                  Standbys exist but details are masked — grant
                  <code class="font-mono">pg_monitor</code>
                  to the app user (see README).
                </span>
              <% {:error, _} -> %>
                <span class="opacity-60">Replication status unavailable.</span>
            <% end %>
          </div>
        </div>
      </section>

      <section id="databases" class="grid gap-6 md:grid-cols-2">
        <div
          :for={db <- @databases}
          id={"db-#{db.key}"}
          class="card border border-base-300 bg-base-100"
        >
          <div class="card-body gap-3">
            <h2 class="text-xs font-semibold uppercase tracking-wider opacity-60">
              {db.key} database <span class="normal-case tracking-normal">— {db.label}</span>
            </h2>
            <ul class="menu w-full p-0">
              <li :for={table <- db.tables}>
                <.link navigate={~p"/tables/#{db.key}/#{table.name}"} class="flex justify-between">
                  <span class="font-mono text-sm">{table.name}</span>
                  <span class="badge badge-ghost badge-sm tabular-nums">~{table.rows_est} rows</span>
                </.link>
              </li>
            </ul>
            <div :if={db.key == "analytics"} class="space-y-2">
              <p class="text-xs opacity-60">
                Second CNPG cluster; a visit row is written here on every page load.
                <span :if={@analytics? && @visits.last}>
                  Last: <span class="font-mono">{@visits.last.inserted_at}</span>
                </span>
              </p>
              <div class="flex items-center gap-3">
                <button
                  id="simulate-traffic"
                  phx-click="simulate"
                  class="btn btn-primary btn-sm"
                  disabled={@burst_left > 0}
                >
                  <span :if={@burst_left > 0} class="loading loading-spinner loading-xs"></span>
                  <%= if @burst_left > 0 do %>
                    Writing… {@burst_left} left
                  <% else %>
                    Simulate traffic (20 rows)
                  <% end %>
                </button>
                <span class="text-xs opacity-60">
                  Watch the visit count climb — open a second window, it climbs there too.
                </span>
              </div>
            </div>
            <p :if={db.key == "main"} class="text-xs opacity-60">
              Browsing reads go through the replica pool (demo-db-ro).
            </p>
          </div>
        </div>
      </section>

      <section id="notes" class="card border border-base-300 bg-base-100">
        <div class="card-body gap-3">
          <h2 class="text-xs font-semibold uppercase tracking-wider opacity-60">
            Notes — writes to the primary
          </h2>
          <.form for={@form} id="note-form" phx-submit="save" class="join w-full">
            <input
              type="text"
              name={@form[:body].name}
              value={Phoenix.HTML.Form.normalize_value("text", @form[:body].value)}
              placeholder="Write a note — stored in demo-db via demo-db-rw"
              class="input join-item w-full"
            />
            <button class="btn btn-primary join-item">Save</button>
          </.form>
          <ul id="note-list" class="divide-y divide-base-200">
            <li :for={note <- @notes} id={"note-#{note.id}"} class="flex justify-between gap-4 py-2">
              <span class="text-sm">{note.body}</span>
              <span class="text-xs opacity-60 font-mono tabular-nums whitespace-nowrap">
                {note.inserted_at}
              </span>
            </li>
          </ul>
          <p :if={@notes == []} class="text-sm opacity-60">No notes yet — write the first one.</p>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
