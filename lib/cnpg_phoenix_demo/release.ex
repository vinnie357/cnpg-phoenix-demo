defmodule CnpgPhoenixDemo.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :cnpg_phoenix_demo

  def migrate do
    load_app()

    # Only migrate repos that are actually configured at runtime — the
    # analytics repo is optional (no ANALYTICS_DATABASE_URL ⇒ no config
    # ⇒ skipped instead of crashing boot).
    for repo <- repos(), Application.get_env(@app, repo) != nil do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
