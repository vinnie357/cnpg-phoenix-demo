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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-lg font-semibold">CloudNativePG + Phoenix demo</h1>
      <p class="text-sm opacity-70">
        Postgres: {@version} · app pod <span id="pod-name">{@pod}</span>
        on node <span id="node-name">{@node}</span>
      </p>

      <section id="topology" class="card bg-base-200 p-4 text-sm space-y-2">
        <h2 class="font-semibold">Topology — where each connection pool landed</h2>
        <table class="table-auto w-full text-left">
          <thead>
            <tr class="opacity-60">
              <th class="pr-4">pool</th>
              <th class="pr-4">dialed</th>
              <th class="pr-4">server</th>
              <th class="pr-4">CNPG cluster</th>
              <th>role</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={t <- @topology} id={"topo-#{t.role |> String.replace(~r/\W+/, "-")}"}>
              <td class="pr-4 font-semibold">{t.role}</td>
              <td class="pr-4">{t.dialed}</td>
              <td class="pr-4">{t.server}</td>
              <td class="pr-4">{t.cluster_name || "—"}</td>
              <td>
                <%= case t.in_recovery do %>
                  <% true -> %>
                    <span class="text-info">hot standby</span>
                  <% false -> %>
                    <span class="text-success">primary</span>
                  <% _ -> %>
                    —
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
        <div id="replication">
          <%= case @replication do %>
            <% {:ok, []} -> %>
              <p class="opacity-60">No streaming standbys (single-instance cluster).</p>
            <% {:ok, standbys} -> %>
              <p>
                Streaming standbys (pg_stat_replication):
                <span :for={s <- standbys} class="mr-2 font-semibold">
                  {s.name} <span class="opacity-60">({s.state}/{s.sync})</span>
                </span>
              </p>
            <% {:error, :needs_grant} -> %>
              <p class="opacity-60">
                Standbys exist but details are masked — grant pg_monitor to the app user
                (see README).
              </p>
            <% {:error, _} -> %>
              <p class="opacity-60">Replication status unavailable.</p>
          <% end %>
        </div>
      </section>

      <section :if={@analytics?} id="visits" class="card bg-base-200 p-4 text-sm">
        <h2 class="font-semibold">Analytics (second CNPG cluster)</h2>
        <p>
          Page visits recorded: <span id="visit-count" class="font-semibold">{@visits.total}</span>
          <span :if={@visits.last} class="opacity-60">
            — last from pod {@visits.last.pod} at {@visits.last.inserted_at}
          </span>
        </p>
      </section>

      <section id="databases" class="card bg-base-200 p-4 text-sm space-y-2">
        <h2 class="font-semibold">Databases — browse tables</h2>
        <div :for={db <- @databases} id={"db-#{db.key}"}>
          <h3 class="font-semibold opacity-80">
            {db.key} <span class="opacity-60">— {db.label}</span>
          </h3>
          <ul class="list-disc pl-5">
            <li :for={table <- db.tables}>
              <.link navigate={~p"/tables/#{db.key}/#{table.name}"} class="underline">
                {table.name}
              </.link>
              <span class="opacity-60">~{table.rows_est} rows</span>
            </li>
          </ul>
        </div>
      </section>

      <section id="notes" class="space-y-4">
        <.form for={@form} id="note-form" phx-submit="save">
          <.input
            field={@form[:body]}
            type="text"
            label="New note"
            placeholder="Stored in CNPG Postgres"
          />
          <.button>Save note</.button>
        </.form>

        <ul id="note-list" class="list-disc pl-5 space-y-1">
          <li :for={note <- @notes} id={"note-#{note.id}"}>
            {note.body}
            <span class="text-xs opacity-60">{note.inserted_at}</span>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
