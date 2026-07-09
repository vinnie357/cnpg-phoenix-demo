defmodule CnpgPhoenixDemoWeb.TableLive do
  use CnpgPhoenixDemoWeb, :live_view

  alias CnpgPhoenixDemo.Databases

  @impl true
  def mount(%{"repo" => repo_key, "table" => table}, _session, socket) do
    with {:ok, repo} <- Databases.repo_for_key(repo_key),
         {:ok, data} <- Databases.table_rows(repo, table) do
      {:ok,
       socket
       |> assign(:page_title, table)
       |> assign(:repo_key, repo_key)
       |> assign(:table, table)
       |> assign(:data, data)}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Unknown table")
         |> push_navigate(to: ~p"/")}
    end
  end

  defp display(value) when is_binary(value), do: value
  defp display(nil), do: ""
  defp display(%DateTime{} = dt), do: to_string(dt)
  defp display(%NaiveDateTime{} = dt), do: to_string(dt)
  defp display(value), do: inspect(value)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="breadcrumbs text-sm">
        <ul>
          <li><.link navigate={~p"/"}>Overview</.link></li>
          <li><span class="opacity-60">{@repo_key} database</span></li>
          <li><span class="font-mono">{@table}</span></li>
        </ul>
      </div>

      <div class="flex items-baseline gap-3">
        <h1 class="text-2xl font-semibold font-mono">{@table}</h1>
        <span class="badge badge-ghost badge-sm">first 20 rows</span>
      </div>

      <section class="card border border-base-300 bg-base-100">
        <div class="card-body">
          <div class="overflow-x-auto">
            <table id="table-rows" class="table table-sm table-zebra">
              <thead>
                <tr>
                  <th :for={col <- @data.columns} class="font-mono">{col}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @data.rows}>
                  <td :for={value <- row} class="align-top text-sm tabular-nums">
                    {display(value)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={@data.rows == []} class="text-sm opacity-60">Table is empty.</p>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
