defmodule CnpgPhoenixDemo.Analytics do
  @moduledoc """
  Page-visit events stored in the second CNPG cluster (metrics-db) —
  a different data domain from notes.
  """

  import Ecto.Query

  alias CnpgPhoenixDemo.Analytics.Visit
  alias CnpgPhoenixDemo.AnalyticsRepo

  @topic "visits"

  def configured? do
    Application.get_env(:cnpg_phoenix_demo, AnalyticsRepo) != nil
  end

  def subscribe do
    Phoenix.PubSub.subscribe(CnpgPhoenixDemo.PubSub, @topic)
  end

  def record_visit(pod, node) do
    result =
      %Visit{}
      |> Visit.changeset(%{"pod" => pod, "node" => node})
      |> AnalyticsRepo.insert()

    with {:ok, visit} <- result do
      :ok = Phoenix.PubSub.broadcast(CnpgPhoenixDemo.PubSub, @topic, {:visit_recorded, visit})
      {:ok, visit}
    end
  end

  def stats do
    total = AnalyticsRepo.aggregate(Visit, :count)
    last = AnalyticsRepo.one(from v in Visit, order_by: [desc: v.id], limit: 1)
    %{total: total, last: last}
  end
end
