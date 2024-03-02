defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Callback do
  alias Lexical.Ast.Env
  alias Lexical.Completion.Translatable
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion

  defimpl Translatable, for: Candidate.Callback do
    def translate(callback, _builder, %Env{} = env) do
      %Candidate.Callback{
        name: name,
        argument_names: arg_names,
        summary: summary
      } = callback

      insert_text =
        impl_line(callback, env) <>
          "def #{name}(#{arg_text(arg_names)}) do" <>
          "\n\t$0\nend"

      Completion.Builder.snippet(env, insert_text,
        label: "#{name}(#{Enum.join(arg_names, ", ")})",
        kind: :interface,
        detail: detail(callback),
        sort_text: sort_text(callback),
        filter_text: "def #{name}",
        documentation: summary
      )
    end

    # add tab stops and join with ", "
    defp arg_text(args) do
      args
      |> Enum.with_index(fn arg, i ->
        "${#{i + 1}:#{arg}}"
      end)
      |> Enum.join(", ")
    end

    # elixir_sense suggests child_spec/1 as a callback as it's a common idiom,
    # but not an actual callback of behaviours like GenServer.
    defp impl_line(%{name: "child_spec"}, _env) do
      ""
    end

    # It's generally safe adding `@impl true` to callbacks as Elixir warns
    # of conflicting behaviours, and they're virtually non-existent anyway.
    defp impl_line(%{}, _env) do
      "@impl true\n"
    end

    defp detail(%{name: "child_spec"}) do
      "supervision specification"
    end

    defp detail(%{origin: origin, metadata: %{optional: true}}) do
      "#{origin} callback"
    end

    defp detail(%{origin: origin, metadata: %{optional: false}}) do
      "#{origin} callback (required)"
    end

    # cribbed from the callable translation for now.
    defp sort_text(%{name: name, arity: arity}) do
      normalized_arity =
        arity
        |> Integer.to_string()
        |> String.pad_leading(3, "0")

      "#{name}:#{normalized_arity}"
    end
  end
end
