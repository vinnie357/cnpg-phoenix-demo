defmodule CnpgPhoenixDemo.Analytics do
  @moduledoc """
  Page-visit events stored in the second CNPG cluster (metrics-db) —
  a different data domain from notes.
  """

  import Ecto.Query

  alias CnpgPhoenixDemo.Analytics.Visit
  alias CnpgPhoenixDemo.AnalyticsRepo

  def configured? do
    Application.get_env(:cnpg_phoenix_demo, AnalyticsRepo) != nil
  end

  def record_visit(pod, node) do
    %Visit{}
    |> Visit.changeset(%{"pod" => pod, "node" => node})
    |> AnalyticsRepo.insert()
  end

  def stats do
    total = AnalyticsRepo.aggregate(Visit, :count)
    last = AnalyticsRepo.one(from v in Visit, order_by: [desc: v.id], limit: 1)
    %{total: total, last: last}
  end
end
