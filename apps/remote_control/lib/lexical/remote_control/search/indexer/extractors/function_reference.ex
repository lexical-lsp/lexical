defmodule Lexical.RemoteControl.Search.Indexer.Extractors.FunctionReference do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Formats
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Metadata
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  @excluded_kernel_macros :macros
                          |> Kernel.__info__()
                          |> Enum.reduce([], fn {name, _arity}, acc ->
                            string_name = Atom.to_string(name)

                            if String.starts_with?(string_name, "def") do
                              [name | acc]
                            else
                              acc
                            end
                          end)

  # syntax specific functions to exclude from our matches
  @excluded_operators ~w[-> && ** ++ -- .. "..//" ! <> =~ @ |> | || * + - / != !== < <= == === > >=]a
  @excluded_keywords ~w[and if import in not or raise require try use]a
  @excluded_special_forms :macros
                          |> Kernel.SpecialForms.__info__()
                          |> Keyword.keys()

  @excluded_functions @excluded_kernel_macros
                      |> Enum.concat(@excluded_operators)
                      |> Enum.concat(@excluded_special_forms)
                      |> Enum.concat(@excluded_keywords)

  # Dynamic calls using apply apply(Module, :function, [1, 2])
  def extract(
        {:apply, apply_meta,
         [
           {:__aliases__, _, module},
           {:__block__, _, [function_name]},
           {:__block__, _,
            [
              arg_list
            ]}
         ]},
        %Reducer{} = reducer
      )
      when is_list(arg_list) and is_atom(function_name) do
    entry = entry(reducer, apply_meta, apply_meta, module, function_name, arg_list)
    {:ok, entry, nil}
  end

  # Dynamic call via Kernel.apply Kernel.apply(Module, :function, [1, 2])
  def extract(
        {{:., _, [{:__aliases__, start_metadata, [:Kernel]}, :apply]}, apply_meta,
         [
           {:__aliases__, _, module},
           {:__block__, _, [function_name]},
           {:__block__, _, [arg_list]}
         ]},
        %Reducer{} = reducer
      )
      when is_list(arg_list) and is_atom(function_name) do
    entry = entry(reducer, start_metadata, apply_meta, module, function_name, arg_list)
    {:ok, entry, nil}
  end

  # remote function OtherModule.foo(:arg), OtherModule.foo() or OtherModule.foo
  def extract(
        {{:., _, [{:__aliases__, start_metadata, module}, fn_name]}, end_metadata, args},
        %Reducer{} = reducer
      )
      when is_atom(fn_name) do
    entry = entry(reducer, start_metadata, end_metadata, module, fn_name, args)

    {:ok, entry}
  end

  # local function capture &downcase/1
  def extract(
        {:/, _, [{fn_name, end_metadata, nil}, {:__block__, arity_meta, [arity]}]},
        %Reducer{} = reducer
      ) do
    position = Reducer.position(reducer)
    {module, _, _} = Analysis.resolve_local_call(reducer.analysis, position, fn_name, arity)
    entry = entry(reducer, end_metadata, arity_meta, module, fn_name, arity)
    {:ok, entry, nil}
  end

  # Function capture with arity: &OtherModule.foo/3
  def extract(
        {:&, _,
         [
           {:/, _,
            [
              {{:., _, [{:__aliases__, start_metadata, module}, function_name]}, _, []},
              {:__block__, end_metadata, [arity]}
            ]}
         ]},
        %Reducer{} = reducer
      ) do
    entry = entry(reducer, start_metadata, end_metadata, module, function_name, arity)

    # we return nil here to stop analysis from progressing down the syntax tree,
    # because if it did, the function head that deals with normal calls will pick
    # up the rest of the call and return a reference to MyModule.function/0, which
    # is incorrect
    {:ok, entry, nil}
  end

  def extract({exclude, _meta, _args}, %Reducer{}) when exclude in @excluded_functions do
    :ignored
  end

  # local function call foo() foo(arg)
  def extract({fn_name, meta, args}, %Reducer{} = reducer)
      when is_atom(fn_name) and is_list(args) do
    arity = call_arity(args)
    position = Reducer.position(reducer)

    {module, _, _} = Analysis.resolve_local_call(reducer.analysis, position, fn_name, arity)

    entry = entry(reducer, meta, meta, [module], fn_name, args)

    {:ok, entry}
  end

  def extract(_ast, _reducer) do
    :ignored
  end

  defp entry(
         %Reducer{} = reducer,
         start_metadata,
         end_metadata,
         module,
         function_name,
         args_arity
       ) do
    arity = call_arity(args_arity)
    block = Reducer.current_block(reducer)
    range = get_reference_range(reducer.analysis.document, start_metadata, end_metadata)
    {:ok, module} = Ast.expand_alias(module, reducer.analysis, range.start)
    mfa = "#{Formats.module(module)}.#{function_name}/#{arity}"

    Entry.reference(
      reducer.analysis.document.path,
      block.ref,
      block.parent_ref,
      mfa,
      :function,
      range,
      Application.get_application(module)
    )
  end

  defp get_reference_range(document, start_metadata, end_metadata) do
    {start_line, start_column} = start_position(start_metadata)
    start_position = Position.new(document, start_line, start_column)
    has_parens? = not Keyword.get(end_metadata, :no_parens, false)

    {end_line, end_column} =
      with nil <- Metadata.position(end_metadata, :closing) do
        position = Metadata.position(end_metadata)

        if has_parens? do
          position
        else
          {line, column} = position
          # add two for the parens
          {line, column + 2}
        end
      end

    end_position = Position.new(document, end_line, end_column)
    Range.new(start_position, end_position)
  end

  defp start_position(metadata) do
    Metadata.position(metadata)
  end

  defp call_arity(args) when is_list(args), do: length(args)
  defp call_arity(arity) when is_integer(arity), do: arity
  defp call_arity(_), do: 0
end
