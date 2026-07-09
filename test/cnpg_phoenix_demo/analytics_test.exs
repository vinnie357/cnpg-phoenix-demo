defmodule CnpgPhoenixDemo.AnalyticsTest do
  use CnpgPhoenixDemo.DataCase, async: true

  alias CnpgPhoenixDemo.Analytics

  test "record_visit/2 round-trips through the analytics database" do
    {:ok, visit} = Analytics.record_visit("pod-1", "node-a")

    assert visit.pod == "pod-1"
    assert %{total: 1, last: %{pod: "pod-1", node: "node-a"}} = Analytics.stats()
  end
end
