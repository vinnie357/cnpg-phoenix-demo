defmodule CnpgPhoenixDemo.DatabasesTest do
  use CnpgPhoenixDemo.DataCase, async: true

  alias CnpgPhoenixDemo.Databases
  alias CnpgPhoenixDemo.Notes

  test "list_tables/1 includes the notes table and table_rows/2 returns its rows" do
    {:ok, _note} = Notes.create_note(%{"body" => "browse me"})

    repo = Databases.replica_repo()
    assert Enum.any?(Databases.list_tables(repo), &(&1.name == "notes"))

    assert {:ok, %{columns: columns, rows: rows}} = Databases.table_rows(repo, "notes")
    assert "body" in columns
    assert Enum.any?(rows, fn row -> "browse me" in row end)
  end

  test "table_rows/2 rejects identifiers outside the catalog allowlist" do
    assert {:error, :unknown_table} =
             Databases.table_rows(Databases.replica_repo(), "notes; DROP TABLE notes--")
  end
end
