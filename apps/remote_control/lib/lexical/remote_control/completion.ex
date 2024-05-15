defmodule Lexical.RemoteControl.Completion do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Env
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.CodeMod.Format
  alias Lexical.RemoteControl.Completion.Candidate

  import Document.Line

  @built_in_locals_without_parens [
    # Special forms
    alias: 1,
    alias: 2,
    case: 2,
    cond: 1,
    for: :*,
    import: 1,
    import: 2,
    quote: 1,
    quote: 2,
    receive: 1,
    require: 1,
    require: 2,
    try: 1,
    with: :*,

    # Kernel
    def: 1,
    def: 2,
    defp: 1,
    defp: 2,
    defguard: 1,
    defguardp: 1,
    defmacro: 1,
    defmacro: 2,
    defmacrop: 1,
    defmacrop: 2,
    defmodule: 2,
    defdelegate: 2,
    defexception: 1,
    defoverridable: 1,
    defstruct: 1,
    destructure: 2,
    raise: 1,
    raise: 2,
    reraise: 2,
    reraise: 3,
    if: 2,
    unless: 2,
    use: 1,
    use: 2,

    # Stdlib,
    defrecord: 2,
    defrecord: 3,
    defrecordp: 2,
    defrecordp: 3,

    # Testing
    assert: 1,
    assert: 2,
    assert_in_delta: 3,
    assert_in_delta: 4,
    assert_raise: 2,
    assert_raise: 3,
    assert_receive: 1,
    assert_receive: 2,
    assert_receive: 3,
    assert_received: 1,
    assert_received: 2,
    doctest: 1,
    doctest: 2,
    refute: 1,
    refute: 2,
    refute_in_delta: 3,
    refute_in_delta: 4,
    refute_receive: 1,
    refute_receive: 2,
    refute_receive: 3,
    refute_received: 1,
    refute_received: 2,
    setup: 1,
    setup: 2,
    setup_all: 1,
    setup_all: 2,
    test: 1,
    test: 2,

    # Mix config
    config: 2,
    config: 3,
    import_config: 1
  ]

  def elixir_sense_expand(%Env{} = env) do
    {doc_string, position} = strip_struct_operator(env)

    line = position.line
    character = position.character
    hint = ElixirSense.Core.Source.prefix(doc_string, line, character)

    if String.trim(hint) == "" do
      []
    else
      {_formatter, opts} = Format.formatter_for_file(env.project, env.document.path)

      locals_without_parens =
        Keyword.get(opts, :locals_without_parens, []) ++ @built_in_locals_without_parens

      for suggestion <- ElixirSense.suggestions(doc_string, line, character),
          candidate = from_elixir_sense(suggestion, locals_without_parens),
          candidate != nil do
        candidate
      end
    end
  end

  defp from_elixir_sense(suggestion, locals_without_parens) do
    suggestion
    |> Candidate.from_elixir_sense()
    |> maybe_suppress_parens(locals_without_parens)
  end

  defp maybe_suppress_parens(%struct{} = candidate, locals_without_parens)
       when struct in [Candidate.Function, Candidate.Macro] do
    atom_name = String.to_atom(candidate.name)
    suppress_parens? = local_without_parens?(atom_name, candidate.arity, locals_without_parens)

    %{candidate | parens: not suppress_parens?}
  end

  defp maybe_suppress_parens(candidate, _), do: candidate

  defp local_without_parens?(fun, arity, locals_without_parens) do
    arity > 0 and
      Enum.any?(locals_without_parens, fn
        {^fun, :*} -> true
        {^fun, ^arity} -> true
        _ -> false
      end)
  end

  def struct_fields(%Analysis{} = analysis, %Position{} = position) do
    container_struct_module =
      analysis
      |> Lexical.Ast.cursor_path(position)
      |> container_struct_module()

    with {:ok, struct_module} <-
           RemoteControl.Analyzer.expand_alias(container_struct_module, analysis, position),
         true <- function_exported?(struct_module, :__struct__, 0) do
      struct_module
      |> struct()
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.map(&Candidate.StructField.new(&1, struct_module))
    else
      _ -> []
    end
  end

  defp container_struct_module(cursor_path) do
    Enum.find_value(cursor_path, fn
      # current module struct: `%__MODULE__{|}`
      {:%, _, [{:__MODULE__, _, _} | _]} -> [:__MODULE__]
      # struct leading by current module: `%__MODULE__.Struct{|}`
      {:%, _, [{:__aliases__, _, [{:__MODULE__, _, _} | tail]} | _]} -> [:__MODULE__ | tail]
      # Struct leading by alias or just a aliased Struct: `%Struct{|}`, `%Project.Struct{|}`
      {:%, _, [{:__aliases__, _, aliases} | _]} -> aliases
      _ -> nil
    end)
  end

  # HACK: This fixes ElixirSense struct completions for certain cases.
  # We should try removing when we update or remove ElixirSense.
  defp strip_struct_operator(%Env{} = env) do
    with true <- Env.in_context?(env, :struct_reference),
         {:ok, completion_length} <- fetch_struct_completion_length(env) do
      column = env.position.character
      percent_position = column - (completion_length + 1)

      new_line_start = String.slice(env.line, 0, percent_position - 1)
      new_line_end = String.slice(env.line, percent_position..-1//1)
      new_line = [new_line_start, new_line_end]
      new_position = Position.new(env.document, env.position.line, env.position.character - 1)
      line_to_replace = env.position.line

      stripped_text =
        env.document.lines
        |> Enum.with_index(1)
        |> Enum.reduce([], fn
          {line(ending: ending), ^line_to_replace}, acc ->
            [acc, new_line, ending]

          {line(text: line_text, ending: ending), _}, acc ->
            [acc, line_text, ending]
        end)
        |> IO.iodata_to_binary()

      {stripped_text, new_position}
    else
      _ ->
        doc_string = Document.to_string(env.document)
        {doc_string, env.position}
    end
  end

  defp fetch_struct_completion_length(env) do
    case Code.Fragment.cursor_context(env.prefix) do
      {:struct, {:dot, {:alias, struct_name}, []}} ->
        # add one because of the trailing period
        {:ok, length(struct_name) + 1}

      {:struct, {:local_or_var, local_name}} ->
        {:ok, length(local_name)}

      {:struct, struct_name} ->
        {:ok, length(struct_name)}

      {:local_or_var, local_name} ->
        {:ok, length(local_name)}
    end
  end
end
