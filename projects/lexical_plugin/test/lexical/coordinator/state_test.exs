defmodule Lexical.Plugin.Coordinator.StateTest do
  alias Lexical.Document
  alias Lexical.Plugin.Coordinator.State
  alias Lexical.Plugin

  use ExUnit.Case

  setup do
    start_supervised!(Plugin.Supervisor)
    Plugin.clear_config()

    {:ok, state: State.new()}
  end

  test "with no configured plugins" do
    assert {[], _} = State.run_all(%State{}, nil, :diagnostic, 50)
  end

  defmodule FailsInit do
    use Plugin.V1.Diagnostic, name: :fails_init

    def init do
      {:error, :failed}
    end

    def handle(subject) do
      {:ok, [subject]}
    end
  end

  test "a plugin is deactivated if it fails to initialize" do
    assert :error = Plugin.register(FailsInit)
    refute :fails_init in Plugin.enabled_plugins()
  end

  defmodule Echo do
    use Plugin.V1.Diagnostic, name: :echo

    def handle(subject) do
      {:ok, [subject]}
    end
  end

  defmodule MultipleResults do
    use Plugin.V1.Diagnostic, name: :multiple_results

    def handle(subject) do
      {:ok, [subject, subject]}
    end
  end

  describe "plugins completing successfully" do
    test "results are returned for a single plugin", %{state: state} do
      Plugin.register(Echo)
      doc = %Document{}
      assert {[^doc], _} = State.run_all(state, doc, :diagnostic, 50)
    end

    test "results are aggregated for multiple plugins", %{state: state} do
      Plugin.register(Echo)
      Plugin.register(MultipleResults)

      doc = %Document{}
      assert {[^doc, ^doc, ^doc], _} = State.run_all(state, doc, :diagnostic, 50)
    end
  end

  describe "failure modes" do
    defmodule TimesOut do
      use Plugin.V1.Diagnostic, name: :times_out

      def handle(subject) do
        Process.sleep(5000)
        {:ok, [subject]}
      end
    end

    defmodule Crashes do
      use Plugin.V1.Diagnostic, name: :crashes

      def handle(subject) do
        45 = subject
        {:ok, [subject]}
      end
    end

    defmodule Errors do
      use Plugin.V1.Diagnostic, name: :errors

      def handle(_) do
        {:error, :invalid_subject}
      end
    end

    defmodule BadReturn do
      use Plugin.V1.Diagnostic, name: :bad_return

      def handle(subject) do
        {:ok, subject}
      end
    end

    test "timeouts are logged", %{state: state} do
      Plugin.register(TimesOut)

      assert {[], state} = State.run_all(state, %Document{}, :diagnostic, 50)
      assert State.failure_count(state, TimesOut) == 1
    end

    test "crashing plugins are logged", %{state: state} do
      Plugin.register(Crashes)
      assert {[], state} = State.run_all(state, %Document{}, :diagnostic, 50)
      assert State.failure_count(state, Crashes) == 1
    end

    test "a plugin that returns an error is logged", %{state: state} do
      Plugin.register(Errors)

      assert {[], state} = State.run_all(state, %Document{}, :diagnostic, 50)
      assert State.failure_count(state, Errors) == 1
    end

    test "a plugin that doesn't return a list is logged", %{state: state} do
      Plugin.register(BadReturn)

      assert {[], state} = State.run_all(state, %Document{}, :diagnostic, 50)
      assert State.failure_count(state, BadReturn) == 1
    end

    test "a plugin is disabled if it fails 3 times", %{state: state} do
      Plugin.register(Crashes)

      assert :crashes in Plugin.enabled_plugins()

      Enum.reduce(1..10, state, fn _, state ->
        {_, state} = State.run_all(state, %Document{}, :diagnostic, 50)
        state
      end)

      refute :crashes in Plugin.enabled_plugins()
    end
  end
end
