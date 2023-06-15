defmodule Lexical.Plugin.CoordinatorTest do
  alias Lexical.Document
  alias Lexical.Plugin
  alias Lexical.Project

  use ExUnit.Case

  setup do
    {:ok, _} = start_supervised(Plugin.Supervisor)
    {:ok, _} = start_supervised(Plugin.Coordinator)

    on_exit(fn ->
      Plugin.clear_config()
    end)

    :ok
  end

  defmodule Echo do
    alias Lexical.Document
    alias Lexical.Project

    use Lexical.Plugin.V1.Diagnostic, name: :report_back

    def handle(%Document{} = doc) do
      {:ok, [doc]}
    end

    def handle(%Project{} = project) do
      {:ok, [project]}
    end
  end

  def with_echo_plugin(_) do
    Plugin.register(Echo)
  end

  def notifier do
    me = self()
    &send(me, &1)
  end

  describe "registering a plugin" do
    test "works the first time" do
      assert :ok = Plugin.register(Echo)
      assert :report_back in Plugin.enabled_plugins()
    end

    test "fails the second time" do
      assert :ok = Plugin.register(Echo)
      assert :error = Plugin.register(Echo)
    end

    test "fails for modules that aren't plugins" do
      assert :error = Plugin.register(GenServer)
    end
  end

  describe "applying" do
    setup [:with_echo_plugin]

    test "works with documents" do
      doc = %Document{uri: "bad uri"}

      Plugin.diagnose(doc, notifier())

      assert_receive [^doc]
    end

    test "works with projects" do
      project = %Project{root_uri: "file:///fooo/bar"}
      Plugin.diagnose(project, notifier())

      assert_receive [^project]
    end
  end

  describe "handling exceptional conditions" do
    defmodule Crashy do
      use Lexical.Plugin.V1.Diagnostic, name: :crashy

      def handle(_) do
        raise "Bad"
      end
    end

    defmodule Slow do
      use Lexical.Plugin.V1.Diagnostic, name: :slow

      def handle(_) do
        Process.sleep(500)
        {:ok, []}
      end
    end

    defmodule BadReturn do
      use Lexical.Plugin.V1.Diagnostic, name: :bad_return

      def handle(_) do
        {:ok, 34}
      end
    end

    defmodule Exits do
      use Lexical.Plugin.V1.Diagnostic, name: :exits

      def handle(_) do
        exit(:bad)
        {:ok, []}
      end
    end

    defp make_it_crash do
      for _ <- 1..10 do
        Plugin.diagnose(%Document{}, notifier())
      end
    end

    test "an exiting plugin will not crash the coordinator" do
      Plugin.register(Exits)

      old_pid = Process.whereis(Plugin.Coordinator)
      assert :exits in Plugin.enabled_plugins()
      Plugin.diagnose(%Document{}, notifier())

      assert_receive []

      assert Process.alive?(old_pid)
    end

    test "crashing plugins are disabled" do
      Plugin.register(Crashy)

      assert :crashy in Plugin.enabled_plugins()

      make_it_crash()

      assert_receive []
      assert_receive []
      assert_receive []

      refute :crashy in Plugin.enabled_plugins()
    end

    test "slow plugins are disabled" do
      Plugin.register(Slow)

      assert :slow in Plugin.enabled_plugins()

      make_it_crash()

      assert_receive []
      assert_receive []
      assert_receive []

      refute :slow in Plugin.enabled_plugins()
    end

    test "plugins that don't return lists are disabled" do
      Plugin.register(BadReturn)

      assert :bad_return in Plugin.enabled_plugins()

      make_it_crash()

      assert_receive []
      assert_receive []
      assert_receive []

      refute :bad_return in Plugin.enabled_plugins()
    end
  end
end
