defmodule CnpgPhoenixDemo.Status do
  @moduledoc """
  Surfaces the CloudNativePG wiring: per-connection topology (which CNPG
  cluster and instance each pool landed on), streaming-replication state,
  and the Kubernetes pod/node this replica runs on. Never exposes credentials.
  """

  alias CnpgPhoenixDemo.Analytics
  alias CnpgPhoenixDemo.AnalyticsRepo
  alias CnpgPhoenixDemo.Databases
  alias CnpgPhoenixDemo.Repo

  def version do
    case Repo.query("SELECT version()", []) do
      {:ok, %{rows: [[version]]}} -> version
      {:error, _reason} -> "unavailable"
    end
  end

  @doc """
  One topology row per connection pool: the host the pool dialed (from env,
  never credentials), the server it landed on, the CNPG cluster_name, and
  whether that server is a hot standby (pg_is_in_recovery).
  """
  def topology do
    pools =
      [
        {"primary (writes)", Repo, dialed_host("DATABASE_URL")},
        {"replica (reads)", Databases.replica_repo(),
         dialed_host("DATABASE_RO_URL") || dialed_host("DATABASE_URL")}
      ] ++
        if Analytics.configured?() do
          [{"analytics", AnalyticsRepo, dialed_host("ANALYTICS_DATABASE_URL")}]
        else
          []
        end

    Enum.map(pools, fn {role, repo, dialed} ->
      Map.merge(%{role: role, dialed: dialed || "unknown"}, connection_info(repo))
    end)
  end

  defp connection_info(repo) do
    query = """
    SELECT current_setting('cluster_name'), current_database(), current_user,
           host(inet_server_addr()), inet_server_port(), pg_is_in_recovery()
    """

    case repo.query(query, []) do
      {:ok, %{rows: [[cluster_name, database, user, addr, port, in_recovery]]}} ->
        %{
          cluster_name: if(cluster_name in [nil, ""], do: nil, else: cluster_name),
          database: database,
          user: user,
          server: if(addr, do: "#{addr}:#{port}"),
          in_recovery: in_recovery
        }

      {:error, _reason} ->
        %{cluster_name: nil, database: nil, user: nil, server: "unavailable", in_recovery: nil}
    end
  end

  @doc """
  Streaming standbys as seen from the primary. Postgres NULL-masks the
  walsender columns for roles without pg_monitor — reported as :needs_grant
  so the UI can hint at the fix.
  """
  def replication do
    case Repo.query(
           "SELECT application_name, state, sync_state FROM pg_stat_replication",
           []
         ) do
      {:ok, %{rows: []}} ->
        {:ok, []}

      {:ok, %{rows: rows}} ->
        if Enum.all?(rows, fn [name | _] -> name in [nil, ""] end) do
          {:error, :needs_grant}
        else
          {:ok,
           Enum.map(rows, fn [name, state, sync] -> %{name: name, state: state, sync: sync} end)}
        end

      {:error, _reason} ->
        {:error, :unavailable}
    end
  end

  # host:port a pool dialed, parsed from its env URL — never credentials.
  defp dialed_host(env_var) do
    with url when is_binary(url) <- System.get_env(env_var),
         %URI{host: host} = uri when is_binary(host) <- URI.parse(url) do
      "#{host}:#{uri.port || 5432}"
    else
      _ -> nil
    end
  end

  # In Kubernetes, HOSTNAME is the pod name by default.
  def pod_name, do: System.get_env("HOSTNAME", "unknown")

  # NODE_NAME is injected via the downward API (spec.nodeName fieldRef).
  def node_name, do: System.get_env("NODE_NAME", "unknown")
end
