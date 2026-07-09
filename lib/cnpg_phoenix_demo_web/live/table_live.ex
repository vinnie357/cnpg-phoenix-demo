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
      <p><.link navigate={~p"/"} class="underline">&larr; back</.link></p>
      <h1 class="text-lg font-semibold">
        {@table} <span class="text-sm opacity-60">({@repo_key} database, first 20 rows)</span>
      </h1>

      <div class="overflow-x-auto">
        <table id="table-rows" class="table-auto w-full text-left text-sm">
          <thead>
            <tr class="opacity-60">
              <th :for={col <- @data.columns} class="pr-4">{col}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @data.rows}>
              <td :for={value <- row} class="pr-4 align-top">{display(value)}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p :if={@data.rows == []} class="opacity-60 text-sm">Table is empty.</p>
    </Layouts.app>
    """
  end
end
