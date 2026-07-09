defmodule CnpgPhoenixDemo.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # In the release image the pod migrates on boot so the demo is
    # apply-and-go; the pod crashloops (and is restarted by Kubernetes)
    # until the CNPG cluster is reachable.
    if Application.get_env(:cnpg_phoenix_demo, :migrate_on_boot, false) do
      CnpgPhoenixDemo.Release.migrate()
    end

    children = [
      CnpgPhoenixDemoWeb.Telemetry,
      CnpgPhoenixDemo.Repo,
      {DNSCluster, query: Application.get_env(:cnpg_phoenix_demo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CnpgPhoenixDemo.PubSub},
      # Start a worker by calling: CnpgPhoenixDemo.Worker.start_link(arg)
      # {CnpgPhoenixDemo.Worker, arg},
      # Start to serve requests, typically the last entry
      CnpgPhoenixDemoWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CnpgPhoenixDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CnpgPhoenixDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
