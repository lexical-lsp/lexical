defmodule Lexical.Server.CodeIntelligence.Completion.Translations.ModuleAttribute do
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Candidate.ModuleAttribute

  def translate(%Candidate.ModuleAttribute{name: "@moduledoc"}, builder, env) do
    doc_snippet = ~s(
      @moduledoc """
      $0
      """
    ) |> String.trim()

    with_doc =
      builder.snippet(env, doc_snippet,
        detail: "Module documentation block",
        kind: :property,
        label: "@moduledoc"
      )

    without_doc =
      builder.plain_text(env, "@moduledoc false",
        detail: "Skip module documentation",
        kind: :property,
        label: "@moduledoc"
      )

    [with_doc, without_doc]
  end

  def translate(%Candidate.ModuleAttribute{name: "@doc"}, builder, env) do
    doc_snippet = ~s(
      @doc """
      $0
      """
    ) |> String.trim()

    with_doc =
      builder.snippet(env, doc_snippet,
        detail: "Function documentation",
        kind: :property,
        label: "@doc"
      )

    without_doc =
      builder.plain_text(env, "@doc false",
        detail: "Skip function docs",
        kind: :property,
        label: "@doc"
      )

    [with_doc, without_doc]
  end

  def translate(%Candidate.ModuleAttribute{} = attribute, builder, env) do
    builder.plain_text(env, attribute.name,
      detail: "module attribute",
      kind: :constant,
      label: attribute.name
    )
  end
end
