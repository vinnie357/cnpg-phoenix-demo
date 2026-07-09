defmodule CnpgPhoenixDemoWeb.HomeLive do
  use CnpgPhoenixDemoWeb, :live_view

  alias CnpgPhoenixDemo.Notes
  alias CnpgPhoenixDemo.Status

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "CNPG Phoenix Demo")
     |> assign(:db, Status.database_info())
     |> assign(:connected_host, Status.connected_host())
     |> assign(:pod, Status.pod_name())
     |> assign(:node, Status.node_name())
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-lg font-semibold">CloudNativePG + Phoenix demo</h1>

      <section id="status" class="card bg-base-200 p-4 text-sm space-y-1">
        <h2 class="font-semibold">Cluster wiring</h2>
        <p :if={@db.cluster_name}>
          CNPG cluster: <span id="cnpg-cluster" class="font-semibold">{@db.cluster_name}</span>
          (postgres <code>cluster_name</code>, set by the operator)
        </p>
        <p>
          Connected via <span id="connected-host" class="font-semibold">{@connected_host}</span>
          <span :if={@db.server}>
            → server <span id="pg-server">{@db.server}</span>
          </span>
          <span class="opacity-60">(host from the CNPG-generated secret's <code>uri</code>)</span>
        </p>
        <p>Postgres: <span id="pg-version">{@db.version}</span></p>
        <p>
          Database: <span id="pg-database">{@db.database}</span>
          as user <span id="pg-user">{@db.user}</span>
        </p>
        <p>Pod: <span id="pod-name">{@pod}</span> on node <span id="node-name">{@node}</span></p>
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
