defmodule CnpgPhoenixDemo.Status do
  @moduledoc """
  Surfaces the CloudNativePG wiring: Postgres server version, connected
  database and user, plus the Kubernetes pod and node this replica runs on.
  Never exposes credentials.
  """

  alias CnpgPhoenixDemo.Repo

  @unavailable %{
    version: "unavailable",
    database: "unavailable",
    user: "unavailable",
    cluster_name: nil,
    server: nil
  }

  def database_info do
    query = """
    SELECT version(), current_database(), current_user,
           current_setting('cluster_name'),
           host(inet_server_addr()), inet_server_port()
    """

    case Repo.query(query, []) do
      {:ok, %{rows: [[version, database, user, cluster_name, addr, port]]}} ->
        %{
          version: version,
          database: database,
          user: user,
          # CNPG sets cluster_name to the Cluster resource name; empty on vanilla postgres
          cluster_name: if(cluster_name in [nil, ""], do: nil, else: cluster_name),
          server: if(addr, do: "#{addr}:#{port}")
        }

      {:error, _reason} ->
        @unavailable
    end
  end

  # host:port the app dialed, parsed from DATABASE_URL — never credentials.
  def connected_host do
    with url when is_binary(url) <- System.get_env("DATABASE_URL"),
         %URI{host: host} = uri when is_binary(host) <- URI.parse(url) do
      "#{host}:#{uri.port || 5432}"
    else
      _ -> "unknown"
    end
  end

  # In Kubernetes, HOSTNAME is the pod name by default.
  def pod_name, do: System.get_env("HOSTNAME", "unknown")

  # NODE_NAME is injected via the downward API (spec.nodeName fieldRef).
  def node_name, do: System.get_env("NODE_NAME", "unknown")
end
