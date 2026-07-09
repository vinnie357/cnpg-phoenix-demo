defmodule CnpgPhoenixDemo.Databases do
  @moduledoc """
  Read-only table browser over the connected databases.

  Table names are only ever taken from the server-side catalog allowlist,
  so no user-supplied identifier reaches SQL.
  """

  alias CnpgPhoenixDemo.Analytics
  alias CnpgPhoenixDemo.AnalyticsRepo
  alias CnpgPhoenixDemo.ReplicaRepo

  @row_limit 20

  # Main-DB reads go through the replica pool; tests point :replica_repo at
  # Repo so sandboxed inserts stay visible.
  def replica_repo do
    Application.get_env(:cnpg_phoenix_demo, :replica_repo, ReplicaRepo)
  end

  def browsable_databases do
    main = [{"main", "app database (read via replica)", replica_repo()}]

    if Analytics.configured?() do
      main ++ [{"analytics", "metrics database", AnalyticsRepo}]
    else
      main
    end
  end

  def repo_for_key(key) do
    case List.keyfind(browsable_databases(), key, 0) do
      {_key, _label, repo} -> {:ok, repo}
      nil -> :error
    end
  end

  def list_tables(repo) do
    query = """
    SELECT c.relname, greatest(c.reltuples, 0)::bigint
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r'
    ORDER BY c.relname
    """

    case repo.query(query, []) do
      {:ok, %{rows: rows}} -> Enum.map(rows, fn [name, est] -> %{name: name, rows_est: est} end)
      {:error, _reason} -> []
    end
  end

  def table_rows(repo, table) do
    allowed = repo |> list_tables() |> Enum.map(& &1.name)

    if table in allowed do
      escaped = String.replace(table, "\"", "\"\"")

      case repo.query(~s(SELECT * FROM public."#{escaped}" LIMIT #{@row_limit}), []) do
        {:ok, %{columns: columns, rows: rows}} -> {:ok, %{columns: columns, rows: rows}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :unknown_table}
    end
  end
end
