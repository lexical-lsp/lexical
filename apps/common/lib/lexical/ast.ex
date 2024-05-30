defmodule Lexical.Ast do
  @moduledoc """
  Utilities for analyzing Lexical documents as syntax trees.

  ## Analysis

  The preferred way to use this module is by first passing a document to
  `analyze/1`, which returns a `%Lexical.Ast.Analysis{}` struct that
  will have already parsed and analyzed a significant portion of the
  document, thus reducing the cost of successive operations.

  An analysis looks at the entire AST, and thus may fail if the document
  contains syntax errors that prevent parsing. To a partial analysis up
  to a certain point (usually the cursor position), use `reanalyze_to/2`,
  which analyzes the document up to the given position and can therefore
  be used even if later parts of the document contain syntax errors.

  ## Differences from `Code`

  This module includes functions for parsing documents (`t:Lexical.Document/0`)
  and strings into AST's that can be used with the `Sourceror` API and
  include some additional metadata.

  The structure of code parsed using this module will be slightly
  different than using `Code` directly. The most notable difference is
  that atoms will be wrapped in a `:__block__` node that contains
  additional metadata.

  Consider these two semantically-equivalent lists, for instance:

      iex> list_with_kw_syntax = "[foo: :bar]"
      iex> list_with_tuple_syntax = "[{:foo, :bar}]"

  By default, `Code.string_to_quoted/1` does not differentiate between them:

      iex> list_with_kw_syntax |> Code.string_to_quoted()
      {:ok, [foo: :bar]}

      iex> list_with_tuple_syntax |> Code.string_to_quoted()
      {:ok, [foo: :bar]}

  In contrast, `Lexical.Ast.from/1` does:

      iex> list_with_kw_syntax |> Lexical.Ast.from()
      {:ok,
       {:__block__, [closing: [line: 1, column: 11], line: 1, column: 1],
        [
          [
            {{:__block__, [format: :keyword, line: 1, column: 2], [:foo]},
             {:__block__, [line: 1, column: 7], [:bar]}}
          ]
        ]}}

      iex> list_with_tuple_syntax |> Lexical.Ast.from()
      {:ok,
       {:__block__, [closing: [line: 1, column: 14], line: 1, column: 1],
        [
          [
            {:__block__, [closing: [line: 1, column: 13], line: 1, column: 2],
             [
               {{:__block__, [line: 1, column: 3], [:foo]},
                {:__block__, [line: 1, column: 9], [:bar]}}
             ]}
          ]
        ]}}

  """

  alias Future.Code, as: Code
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.Document.Edit
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Sourceror.Zipper

  require Logger
  require Sourceror

  @typedoc "Return value from `Code.Fragment.cursor_context/2`"
  @type cursor_context :: any()

  @typedoc "Return value from `Code.Fragment.surround_context/3`"
  @type surround_context :: any()

  @type parse_error ::
          {location :: keyword(), String.t() | {String.t(), String.t()}, String.t()}

  @type patch :: %{
          optional(:preserve_indentation) => boolean(),
          range: patch_range(),
          change: patch_change()
        }

  @type patch_range :: %{start: patch_position(), end: patch_position()}
  @type patch_position :: [patch_line | patch_column]
  @type patch_line :: {:line, non_neg_integer()}
  @type patch_column :: {:column, non_neg_integer()}
  @type patch_change :: String.t() | (String.t() -> String.t())

  @type short_alias :: atom()
  @type alias_segments :: [short_alias]

  @type comment_metadata :: %{
          line: pos_integer(),
          column: pos_integer(),
          previous_eol_count: non_neg_integer(),
          next_eol_count: non_neg_integer()
        }

  @type position :: Position.t() | {Position.line(), Position.character()}

  @doc """
  Analyzes a document.
  """
  @spec analyze(Document.t()) :: Analysis.t()
  def analyze(%Document{} = document) do
    document
    |> from()
    |> Analysis.new(document)
  end

  @doc """
  Reanalyzes a document up to `position` if `analysis` is not valid.

  This can be used to analyze a fragment of an analyzed document up to
  the cursor position. If the given analysis is already valid, this
  function returns in unchanged.

  Note that the analysis generated for this may give invalid or incomplete
  results for positions after the fragment.

  ## Examples

      iex> analysis = Ast.analyze(invalid_document)
      %Ast.Analysis{valid?: false}

      iex> Ast.reanalyze_to(analysis, cursor_position)
      %Ast.Analysis{} # may be valid or invalid

  """
  @spec reanalyze_to(Analysis.t(), position) :: Analysis.t()
  def reanalyze_to(%Analysis{valid?: false} = analysis, position) do
    %Position{} = position = normalize_position(position, analysis.document)

    analysis.document
    |> fragment(position)
    |> Analysis.new(analysis.document)
  end

  def reanalyze_to(%Analysis{valid?: true} = analysis, _position) do
    analysis
  end

  @doc """
  Returns an AST generated from a valid document or string.
  """
  @spec from(Document.t() | Analysis.t() | String.t()) ::
          {:ok, Macro.t(), comment_metadata()} | {:error, parse_error()}
  def from(%Document{} = document) do
    document
    |> Document.to_string()
    |> from()
  end

  def from(%Analysis{valid?: true} = analysis) do
    comments =
      analysis.comments_by_line
      |> Map.values()
      |> Enum.sort_by(& &1.line)

    {:ok, analysis.ast, comments}
  end

  def from(%Analysis{valid?: false, parse_error: error}), do: error

  def from(s) when is_binary(s) do
    do_string_to_quoted(s)
  end

  @doc """
  Returns an AST fragment from the start of the document to the given position.
  """
  @spec fragment(Document.t(), position) :: {:ok, Macro.t()} | {:error, parse_error()}
  def fragment(%Document{} = document, position) do
    # https://github.com/elixir-lang/elixir/issues/12673#issuecomment-1592845875
    # Note: because of the above issue: Using `cursor_context` + `container_cursor_to_quoted`
    # can't deal with some cases like: `alias Foo.Bar, as: AnotherBar`,
    # so we need to add a new line to make sure we can get the parrent node of the cursor
    %{line: line} = normalize_position(position, document)
    added_new_line_position = Position.new(document, line + 1, 1)
    fragment = Document.fragment(document, added_new_line_position)

    case do_container_cursor_to_quoted(fragment) do
      {:ok, quoted} ->
        {:ok, quoted}

      _error ->
        # https://github.com/elixir-lang/elixir/issues/12673#issuecomment-1626932280
        # NOTE: Adding new line doesn't always work,
        # so we need to try again without adding new line
        document_fragment = Document.fragment(document, position)
        do_container_cursor_to_quoted(document_fragment)
    end
  end

  @doc """
  Parses the given fragment into an AST.
  """
  @spec fragment(String.t()) :: {:ok, Macro.t()} | {:error, parse_error()}
  def fragment(s) when is_binary(s) do
    do_container_cursor_to_quoted(s)
  end

  @doc """
  Returns the cursor context of the document at a position.
  """
  @spec cursor_context(Analysis.t() | Document.t(), position) ::
          {:ok, cursor_context()} | {:error, :cursor_context}
  def cursor_context(%Analysis{} = analysis, position) do
    cursor_context(analysis.document, position)
  end

  def cursor_context(%Document{} = document, position) do
    %Position{} = position = normalize_position(position, document)

    document
    |> Document.fragment(position)
    |> do_cursor_context()
  end

  @doc """
  Returns the surround context of the document at a position.
  """
  @spec surround_context(Analysis.t() | Document.t(), position) ::
          {:ok, surround_context()} | {:error, :surround_context}
  def surround_context(%Analysis{} = analysis, position) do
    surround_context(analysis.document, position)
  end

  def surround_context(%Document{} = document, position) do
    %Position{} = position = normalize_position(position, document)

    document
    |> Document.to_string()
    |> do_surround_context(position)
  end

  @doc """
  Returns the path to the innermost node in the document at the given position.

  This function differs from `cursor_path/2` in that it expects a valid
  AST and the returned path will not contain a `:__cursor__` node.
  """
  @spec path_at(Analysis.t() | Document.t(), position) ::
          {:ok, [Macro.t(), ...]} | {:error, :not_found | parse_error()}
  def path_at(%struct{} = document_or_analysis, %Position{} = position)
      when struct in [Document, Analysis] do
    with {:ok, ast, _} <- from(document_or_analysis) do
      path_at(ast, position)
    end
  end

  @spec path_at(Macro.t(), Position.t()) ::
          {:ok, [Macro.t(), ...]} | {:error, :not_found}
  def path_at(ast, %Position{} = position) do
    path = innermost_path(ast, [], &contains_position?(&1, position))

    case path do
      nil -> {:error, :not_found}
      path -> {:ok, path}
    end
  end

  @doc """
  Returns the path to the cursor in a fragment of the document from the
  start to the given position.

  This function differs from `path_at/2` in that it operates on an AST
  fragment as opposed to a full AST and the call never fails, though it
  may return an empty list.
  """
  @spec cursor_path(Analysis.t() | Document.t(), position) :: [Macro.t()]
  def cursor_path(%Analysis{} = analysis, position) do
    cursor_path(analysis.document, position)
  end

  def cursor_path(%Document{} = document, position) do
    %Position{} = position = normalize_position(position, document)
    document_fragment = Document.fragment(document, position)

    case do_container_cursor_to_quoted(document_fragment) do
      {:ok, quoted} ->
        quoted
        |> Future.Macro.path(&match?({:__cursor__, _, _}, &1))
        |> List.wrap()

      _ ->
        []
    end
  end

  @doc """
  Returns a zipper for the document AST focused at the given position.
  """
  @spec zipper_at(Document.t(), Position.t()) :: {:ok, Zipper.t()} | {:error, parse_error()}
  def zipper_at(%Document{} = document, %Position{} = position) do
    with {:ok, ast, _} <- from(document) do
      zipper_at_position(ast, position)
    end
  end

  @doc """
  Returns whether the given AST contains a position.
  """
  @spec contains_position?(Macro.t(), Position.t()) :: boolean()
  def contains_position?(ast, %Position{} = position) do
    case Sourceror.get_range(ast) do
      %{start: start_pos, end: end_pos} ->
        on_same_line? = start_pos[:line] == end_pos[:line] and position.line == start_pos[:line]

        cond do
          on_same_line? ->
            position.character >= start_pos[:column] and position.character <= end_pos[:column]

          position.line == start_pos[:line] ->
            position.character >= start_pos[:column]

          position.line == end_pos[:line] ->
            position.character <= end_pos[:column]

          true ->
            position.line > start_pos[:line] and position.line < end_pos[:line]
        end

      nil ->
        false
    end
  end

  @doc """
  Converts the document to a zipper and traverses the nodes on the given line.

  The given function must accept and return a (potentially modified) zipper.
  To maintain an accumulator, use `traverse_line/4`.
  """
  @spec traverse_line(Document.t(), Position.line(), (Zipper.t() -> Zipper.t())) ::
          {:ok, Zipper.t()} | {:error, parse_error()}
  def traverse_line(%Document{} = document, line_number, fun) when is_integer(line_number) do
    range = one_line_range(document, line_number)
    traverse_in(document, range, fun)
  end

  @spec traverse_line(
          Document.t(),
          Position.line(),
          acc,
          (Zipper.t(), acc -> {Zipper.t(), acc})
        ) ::
          {:ok, Zipper.t(), acc} | {:error, parse_error()}
        when acc: any()
  def traverse_line(%Document{} = document, line_number, acc, fun) when is_integer(line_number) do
    range = one_line_range(document, line_number)
    traverse_in(document, range, acc, fun)
  end

  @doc """
  Converts AST patches to document edits.

  Returns `{:ok, edits}` if all patches are valid and `:error` otherwise.
  """
  @spec patches_to_edits(Document.t(), [patch()]) :: {:ok, [Edit.t()]} | :error
  def patches_to_edits(%Document{} = document, patches) do
    maybe_edits =
      Enum.reduce_while(patches, [], fn patch, edits ->
        case patch_to_edit(document, patch) do
          {:ok, edit} -> {:cont, [edit | edits]}
          error -> {:halt, error}
        end
      end)

    case maybe_edits do
      edits when is_list(edits) -> {:ok, Enum.reverse(edits)}
      error -> error
    end
  end

  @doc """
  Converts a single AST patch to a document edit.

  Returns `{:ok, edit}` if valid and `:error` otherwise.
  """
  @spec patch_to_edit(Document.t(), patch()) :: {:ok, Edit.t()} | :error
  def patch_to_edit(%Document{} = document, %{} = patch) do
    %{change: change, range: %{start: start_pos, end: end_pos}} = patch

    with {:ok, range} <- patch_to_range(document, start_pos, end_pos) do
      {:ok, Edit.new(change, range)}
    end
  end

  # Expands aliases given the rules in the special form
  # https://hexdocs.pm/elixir/1.13.4/Kernel.SpecialForms.html#__aliases__/1
  def reify_alias(current_module, [:"Elixir" | _] = reified) do
    {:ok, [current_module | reified]}
  end

  def reify_alias(current_module, [:__MODULE__ | rest]) do
    {:ok, [current_module | rest]}
  end

  def reify_alias(current_module, [atom | _rest] = reified) when is_atom(atom) do
    {:ok, [current_module | reified]}
  end

  def reify_alias(current_module, [unreified | rest]) do
    env = %Macro.Env{module: current_module}

    case Macro.expand(unreified, env) do
      module when is_atom(module) -> {:ok, [module | rest]}
      _ -> :error
    end
  end

  def reify_alias(current_module, []) do
    {:ok, List.wrap(current_module)}
  end

  # private

  defp do_string_to_quoted(string) when is_binary(string) do
    Code.string_to_quoted_with_comments(string,
      literal_encoder: &{:ok, {:__block__, &2, [&1]}},
      token_metadata: true,
      columns: true,
      unescape: false
    )
  end

  defp do_container_cursor_to_quoted(fragment) when is_binary(fragment) do
    Code.Fragment.container_cursor_to_quoted(fragment,
      literal_encoder: &{:ok, {:__block__, &2, [&1]}},
      token_metadata: true,
      columns: true,
      unescape: false
    )
  end

  defp do_cursor_context(fragment) when is_binary(fragment) do
    case Code.Fragment.cursor_context(fragment) do
      :none -> {:error, :cursor_context}
      context -> {:ok, context}
    end
  end

  defp do_surround_context(fragment, %Position{} = position) when is_binary(fragment) do
    case Code.Fragment.surround_context(fragment, {position.line, position.character}) do
      :none -> {:error, :surround_context}
      context -> {:ok, context}
    end
  end

  defp patch_to_range(document, start_pos, end_pos) do
    with {:ok, start_pos} <- patch_to_position(document, start_pos),
         {:ok, end_pos} <- patch_to_position(document, end_pos) do
      {:ok, Range.new(start_pos, end_pos)}
    end
  end

  defp patch_to_position(document, patch_keyword) do
    with {:ok, line} <- Keyword.fetch(patch_keyword, :line),
         {:ok, column} <- Keyword.fetch(patch_keyword, :column) do
      {:ok, Position.new(document, line, column)}
    end
  end

  defp zipper_at_position(ast, position) do
    zipper =
      ast
      |> Zipper.zip()
      |> Zipper.find(fn node ->
        at_or_after?(node, position)
      end)

    if zipper do
      {:ok, zipper}
    else
      {:error, :not_found}
    end
  end

  # in the future, I'd like to expose functions that only traverse a section of the document,
  # but presently, traverse only follows a subtree, so it won't work for our purposes
  defp traverse_in(%Document{} = document, %Range{} = range, fun) do
    ignore_acc = fn node, acc ->
      {fun.(node), acc}
    end

    case traverse_in(document, range, [], ignore_acc) do
      {:ok, zipper, _} ->
        {:ok, zipper}

      error ->
        error
    end
  end

  defp traverse_in(%Document{} = document, %Range{} = range, acc, fun) do
    with {:ok, zipper} <- zipper_at(document, range.start) do
      {zipper, {_position, acc}} =
        Zipper.traverse_while(
          zipper,
          {{0, 0}, acc},
          fn %Zipper{node: node} = zipper, {last_position, acc} ->
            current_position = node_position(node, last_position)

            if within_range?(current_position, range) do
              {zipper, new_acc} = fun.(zipper, acc)

              {:cont, zipper, {current_position, new_acc}}
            else
              {:skip, zipper, {current_position, acc}}
            end
          end
        )

      {:ok, zipper, acc}
    end
  end

  defp within_range?({current_line, current_column}, %Range{} = range) do
    start_pos = %Position{} = range.start
    end_pos = %Position{} = range.end

    cond do
      current_line == start_pos.line ->
        current_column >= start_pos.character

      current_line == end_pos.line ->
        current_column <= end_pos.character

      true ->
        current_line >= start_pos.line and current_line <= end_pos.line
    end
  end

  defp at_or_after?(node, %Position{} = position) do
    line = get_line(node, 0)
    column = get_column(node, 0)

    line > position.line or (line == position.line and column >= position.character)
  end

  defp one_line_range(%Document{} = document, line_number) do
    start_pos = Position.new(document, line_number, 1)
    end_pos = Position.new(document, line_number + 1, 0)
    Range.new(start_pos, end_pos)
  end

  defp node_position(node, {line, column}) do
    {get_line(node, line), get_column(node, column)}
  end

  defp get_line([{:do, node}], default) do
    get_line(node, default)
  end

  defp get_line({:do, node}, default) do
    get_line(node, default)
  end

  defp get_line(node, default) when is_tuple(node) and tuple_size(node) == 3 do
    Sourceror.get_line(node, default)
  end

  defp get_line(_, default) do
    default
  end

  defp get_column([do: node], default) do
    get_column(node, default)
  end

  defp get_column({:do, node}, default) do
    get_column(node, default)
  end

  defp get_column(node, default) when is_tuple(node) and tuple_size(node) == 3 do
    Sourceror.get_column(node, default)
  end

  defp get_column(_, default) do
    default
  end

  # Similar to `Future.Macro.path/3`, but returns the path to the innermost
  # node for which `fun` returns truthy instead of the path to the first node
  # that returns such.
  defp innermost_path(ast, acc, fun)

  defp innermost_path({form, _, args} = ast, acc, fun) when is_atom(form) do
    acc = [ast | acc]

    if fun.(ast) do
      innermost_path_args(args, acc, fun) || acc
    else
      innermost_path_args(args, acc, fun)
    end
  end

  defp innermost_path({form, _meta, args} = ast, acc, fun) do
    acc = [ast | acc]

    if fun.(ast) do
      innermost_path(form, acc, fun) || innermost_path_args(args, acc, fun) || acc
    else
      innermost_path(form, acc, fun) || innermost_path_args(args, acc, fun)
    end
  end

  defp innermost_path({left, right} = ast, acc, fun) do
    acc = [ast | acc]

    if fun.(ast) do
      innermost_path(left, acc, fun) || innermost_path(right, acc, fun) || acc
    else
      innermost_path(left, acc, fun) || innermost_path(right, acc, fun)
    end
  end

  defp innermost_path(list, acc, fun) when is_list(list) do
    acc = [list | acc]

    if fun.(list) do
      innermost_path_list(list, acc, fun) || acc
    else
      innermost_path_list(list, acc, fun)
    end
  end

  defp innermost_path(ast, acc, fun) do
    if fun.(ast) do
      [ast | acc]
    end
  end

  defp innermost_path_args(atom, _acc, _fun) when is_atom(atom), do: nil

  defp innermost_path_args(list, acc, fun) when is_list(list) do
    innermost_path_list(list, acc, fun)
  end

  defp innermost_path_list([], _acc, _fun) do
    nil
  end

  defp innermost_path_list([arg | args], acc, fun) do
    innermost_path(arg, acc, fun) || innermost_path_list(args, acc, fun)
  end

  defp normalize_position(%Position{} = position, _document), do: position

  defp normalize_position({line, character}, %Document{} = document) do
    Position.new(document, line, character)
  end
end
