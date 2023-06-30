defmodule Lexical.Runner.CoordinatorTest do
  alias Lexical.Document
  alias Lexical.Plugin.Runner
  alias Lexical.Project

  use ExUnit.Case, async: false
  import Lexical.Test.EventualAssertions

  setup do
    {:ok, _} = start_supervised(Runner.Supervisor)
    {:ok, _} = start_supervised(Runner.Coordinator)

    on_exit(fn ->
      Runner.clear_config()
    end)

    :ok
  end

  defmodule Echo do
    alias Lexical.Document
    alias Lexical.Project

    use Lexical.Plugin.V1.Diagnostic, name: :report_back

    def diagnose(%Document{} = doc) do
      {:ok, [doc]}
    end

    def diagnose(%Project{} = project) do
      {:ok, [project]}
    end
  end

  def with_echo_plugin(_) do
    Runner.register(Echo)

    on_exit(fn ->
      Runner.disable(Echo)
    end)
  end

  def notifier do
    me = self()
    &send(me, &1)
  end

  describe "registering a plugin" do
    test "works the first time" do
      assert :ok = Runner.register(Echo)
      assert :report_back in Runner.enabled_plugins()
    end

    test "fails the second time" do
      assert :ok = Runner.register(Echo)
      assert :error = Runner.register(Echo)
    end

    test "fails for modules that aren't plugins" do
      assert :error = Runner.register(GenServer)
    end
  end

  describe "applying" do
    setup [:with_echo_plugin]

    test "works with documents" do
      doc = %Document{uri: "bad uri"}

      Runner.diagnose(doc, notifier())

      assert_receive [^doc]
    end

    test "works with projects" do
      project = %Project{root_uri: "file:///fooo/bar"}
      Runner.diagnose(project, notifier())

      assert_receive [^project]
    end
  end

  describe "handling exceptional conditions" do
    defmodule Crashy do
      use Lexical.Plugin.V1.Diagnostic, name: :crashy

      def diagnose(_) do
        raise "Bad"
      end
    end

    defmodule Slow do
      use Lexical.Plugin.V1.Diagnostic, name: :slow

      def diagnose(_) do
        Process.sleep(500)
        {:ok, []}
      end
    end

    defmodule BadReturn do
      use Lexical.Plugin.V1.Diagnostic, name: :bad_return

      def diagnose(_) do
        {:ok, 34}
      end
    end

    defmodule Exits do
      use Lexical.Plugin.V1.Diagnostic, name: :exits

      def diagnose(_) do
        exit(:bad)
        {:ok, []}
      end
    end

    defp make_it_crash do
      for _ <- 1..10 do
        Runner.diagnose(%Document{}, notifier())
        assert_receive _
      end
    end

    test "an exiting plugin will not crash the coordinator" do
      Runner.register(Exits)

      old_pid = Process.whereis(Runner.Coordinator)
      assert :exits in Runner.enabled_plugins()

      Runner.diagnose(%Document{}, notifier())

      assert_receive [], 500

      assert Process.alive?(old_pid)
    end

    test "crashing plugins are disabled" do
      Runner.register(Crashy)

      assert :crashy in Runner.enabled_plugins()

      make_it_crash()

      refute_eventually :crashy in Runner.enabled_plugins()
    end

    test "slow plugins are disabled" do
      Runner.register(Slow)

      assert :slow in Runner.enabled_plugins()

      make_it_crash()

      refute_eventually :slow in Runner.enabled_plugins()
    end

    test "plugins that don't return lists are disabled" do
      Runner.register(BadReturn)

      assert :bad_return in Runner.enabled_plugins()

      make_it_crash()

      refute_eventually :bad_return in Runner.enabled_plugins()
    end
  end
end
