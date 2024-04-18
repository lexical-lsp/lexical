defmodule Lexical.RemoteControl.CodeIntelligence.Symbols.Document do
  alias Lexical.Document
  alias Lexical.Formats
  alias Lexical.RemoteControl.Search.Indexer.Entry

  defstruct [:name, :type, :range, :detail_range, :detail, children: []]

  def from(%Document{} = document, %Entry{} = entry, children \\ []) do
    case name_and_type(entry.type, entry, document) do
      {name, type} ->
        range = entry.block_range || entry.range

        {:ok,
         %__MODULE__{
           name: name,
           type: type,
           range: range,
           detail_range: entry.range,
           children: children
         }}

      _ ->
        :error
    end
  end

  @do_regex ~r/\s*do\s*$/

  defp name_and_type(function, %Entry{} = entry, %Document{} = document)
       when function in [:public_function, :private_function] do
    fragment = Document.fragment(document, entry.range.start, entry.range.end)

    prefix =
      if function == :public_function do
        "def "
      else
        "defp "
      end

    {prefix <> fragment, function}
  end

  @ignored_attributes ~w[spec doc moduledoc derive impl tag]
  @type_name_regex ~r/@type\s+[^\s]+/

  defp name_and_type(:module_attribute, %Entry{} = entry, document) do
    case String.split(entry.subject, "@") do
      [_, name] when name in @ignored_attributes ->
        nil

      [_, "type"] ->
        type_text = Document.fragment(document, entry.range.start, entry.range.end)

        name =
          case Regex.scan(@type_name_regex, type_text) do
            [[match]] -> match
            _ -> "@type ??"
          end

        {name, :type}

      [_, name] ->
        {"@#{name}", :module_attribute}
    end
  end

  defp name_and_type(ex_unit, %Entry{} = entry, document)
       when ex_unit in [:ex_unit_describe, :ex_unit_setup, :ex_unit_test] do
    name =
      document
      |> Document.fragment(entry.range.start, entry.range.end)
      |> String.trim()
      |> String.replace(@do_regex, "")

    {name, ex_unit}
  end

  defp name_and_type(:struct, %Entry{} = entry, _document) do
    module_name = Formats.module(entry.subject)
    {"%#{module_name}{}", :struct}
  end

  defp name_and_type(type, %Entry{subject: name}, _document) when is_atom(name) do
    {Formats.module(name), type}
  end

  defp name_and_type(type, %Entry{} = entry, _document) do
    {to_string(entry.subject), type}
  end
end
