defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Callback do
  alias Lexical.Ast.Env
  alias Lexical.RemoteControl.Completion.Candidate.Callback
  alias Lexical.Server.CodeIntelligence.Completion.Builder
  alias Lexical.Server.CodeIntelligence.Completion.SortScope
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  defimpl Translatable, for: Callback do
    def translate(callback, _builder, %Env{} = env) do
      %Callback{
        name: name,
        argument_names: arg_names,
        summary: summary
      } = callback

      %Env{line: line} = env

      env
      |> Builder.text_edit_snippet(
        insert_text(name, arg_names),
        line_range(line),
        label: label(name, arg_names),
        kind: :interface,
        detail: detail(callback),
        sort_text: sort_text(callback),
        filter_text: "def #{name}",
        documentation: summary
      )
      |> Builder.set_sort_scope(SortScope.local())
    end

    defp insert_text(name, arg_names)
         when is_binary(name) and is_list(arg_names) do
      impl_line(name) <>
        "def #{name}(#{arg_text(arg_names)}) do" <>
        "\n\t$0\nend"
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
    defp impl_line("child_spec"), do: ""

    # It's generally safe adding `@impl true` to callbacks as Elixir warns
    # of conflicting behaviours, and they're virtually non-existent anyway.
    defp impl_line(_), do: "@impl true\n"

    defp line_range(line) when is_binary(line) do
      start_char =
        case String.split(line, "def", parts: 2) do
          [i, _] -> String.length(i) + 1
          [_] -> 0
        end

      end_char = String.length(line) + 1

      {start_char, end_char}
    end

    defp label(name, arg_names)
         when is_binary(name) and is_list(arg_names) do
      "#{name}(#{Enum.join(arg_names, ", ")})"
    end

    defp detail(%Callback{name: "child_spec"}) do
      "supervision specification"
    end

    defp detail(%Callback{origin: origin, metadata: %{optional: false}}) do
      "#{origin} callback (required)"
    end

    defp detail(%Callback{origin: origin}) do
      "#{origin} callback"
    end

    # cribbed from the Callable translation for now.
    defp sort_text(%Callback{name: name, arity: arity}) do
      normalized_arity =
        arity
        |> Integer.to_string()
        |> String.pad_leading(3, "0")

      "#{name}:#{normalized_arity}"
    end
  end
end
