defmodule CnpgPhoenixDemo.AnalyticsTest do
  use CnpgPhoenixDemo.DataCase, async: true

  alias CnpgPhoenixDemo.Analytics

  test "record_visit/2 round-trips through the analytics database and broadcasts" do
    :ok = Analytics.subscribe()

    {:ok, visit} = Analytics.record_visit("pod-1", "node-a")

    assert visit.pod == "pod-1"
    assert %{total: 1, last: %{pod: "pod-1", node: "node-a"}} = Analytics.stats()
    assert_receive {:visit_recorded, %{pod: "pod-1"}}
  end
end
