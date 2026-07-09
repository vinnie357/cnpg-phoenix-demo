defmodule CnpgPhoenixDemo.Status do
  @moduledoc """
  Surfaces the CloudNativePG wiring: Postgres server version, connected
  database and user, plus the Kubernetes pod and node this replica runs on.
  Never exposes credentials.
  """

  alias CnpgPhoenixDemo.Repo

  def database_info do
    case Repo.query("SELECT version(), current_database(), current_user", []) do
      {:ok, %{rows: [[version, database, user]]}} ->
        %{version: version, database: database, user: user}

      {:error, _reason} ->
        %{version: "unavailable", database: "unavailable", user: "unavailable"}
    end
  end

  # In Kubernetes, HOSTNAME is the pod name by default.
  def pod_name, do: System.get_env("HOSTNAME", "unknown")

  # NODE_NAME is injected via the downward API (spec.nodeName fieldRef).
  def node_name, do: System.get_env("NODE_NAME", "unknown")
end
