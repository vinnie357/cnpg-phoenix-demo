defmodule CnpgPhoenixDemoWeb.HomeLive do
  use CnpgPhoenixDemoWeb, :live_view

  alias CnpgPhoenixDemo.Analytics
  alias CnpgPhoenixDemo.Databases
  alias CnpgPhoenixDemo.Notes
  alias CnpgPhoenixDemo.Status

  @impl true
  def mount(_params, _session, socket) do
    analytics? = Analytics.configured?()

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
     |> assign(:databases, databases_with_tables())
     |> assign(:form, to_form(Notes.change_note()))
     |> assign(:notes, Notes.list_notes())}
  end

  @impl true
  def handle_event("save", %{"note" => params}, socket) do
    case Notes.create_note(params) do
      {:ok, _note} ->
        {:noreply,
         socket
         |> assign(:notes, Notes.list_notes())
         |> assign(:form, to_form(Notes.change_note()))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
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
            <p :if={db.key == "analytics"} class="text-xs opacity-60">
              Second CNPG cluster; a visit row is written here on every page load.
              <span :if={@analytics? && @visits.last}>
                Last: <span class="font-mono">{@visits.last.inserted_at}</span>
              </span>
            </p>
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
