defmodule Lexical.Server.CodeIntelligence.Completion.Translations.ModuleAttribute do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Result.ModuleAttribute

  def translate(%Result.ModuleAttribute{name: "@moduledoc"}, builder, _env) do
    doc_snippet = ~s(
      @moduledoc """
      $0
      """
    ) |> String.trim()

    with_doc =
      builder.snippet(doc_snippet,
        detail: "Module documentation block",
        kind: :property,
        label: "@moduledoc"
      )

    without_doc =
      builder.plain_text("@moduledoc false",
        detail: "Skip module documentation",
        kind: :property,
        label: "@moduledoc"
      )

    [with_doc, without_doc]
  end

  def translate(%Result.ModuleAttribute{name: "@doc"}, builder, _env) do
    doc_snippet = ~s(
      @doc """
      $0
      """
    ) |> String.trim()

    with_doc =
      builder.snippet(doc_snippet,
        detail: "Function documentation",
        kind: :property,
        label: "@doc"
      )

    without_doc =
      builder.plain_text("@doc false",
        detail: "Skip function docs",
        kind: :property,
        label: "@doc"
      )

    [with_doc, without_doc]
  end

  def translate(%Result.ModuleAttribute{} = attribute, builder, _env) do
    builder.plain_text(attribute.name,
      detail: "module attribute",
      kind: :constant,
      label: attribute.name
    )
  end
end
