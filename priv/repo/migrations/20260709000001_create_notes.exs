defmodule CnpgPhoenixDemo.Repo.Migrations.CreateNotes do
  use Ecto.Migration

  def change do
    create table(:notes) do
      add :body, :string, null: false
      timestamps(updated_at: false)
    end
  end
end
