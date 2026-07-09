defmodule CnpgPhoenixDemo.AnalyticsRepo.Migrations.CreateVisits do
  use Ecto.Migration

  def change do
    create table(:visits) do
      add :pod, :string, null: false
      add :node, :string, null: false
      timestamps(updated_at: false)
    end
  end
end
