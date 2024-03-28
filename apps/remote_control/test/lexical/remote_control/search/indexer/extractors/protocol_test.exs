defmodule Lexical.RemoteControl.Search.Indexer.Extractors.ProtocolTest do
  use Lexical.Test.ExtractorCase

  def index(source) do
    do_index(source, &(&1.type in [:protocol, :protocol_implementation]))
  end

  describe "indexing protocol definitions" do
    test "works" do
      {:ok, [protocol], doc} =
        ~q[
          defprotocol Something do
            def activate(thing, environment)
          end
        ]
        |> index()

      assert protocol.type == :protocol
      assert protocol.subtype == :definition
      assert protocol.subject == Something

      expected_block = ~q[
      «defprotocol Something do
        def activate(thing, environment)
      end»
      ]t

      assert decorate(doc, protocol.range) == "defprotocol «Something» do"
      assert decorate(doc, protocol.block_range) == expected_block
    end
  end

  describe "indexing protocol implementations" do
    test "works" do
      {:ok, [protocol], doc} =
        ~q[
          defimpl Something, for: Atom do
            def my_impl(atom, _opts) do
              to_string(atom)
            end
          end
        ]
        |> index()

      assert protocol.type == :protocol_implementation
      assert protocol.subtype == :definition
      assert protocol.subject == Something

      expected_block =
        ~q[
        «defimpl Something, for: Atom do
          def my_impl(atom, _opts) do
            to_string(atom)
          end
        end»
        ]t
        |> String.trim_trailing()

      assert decorate(doc, protocol.range) == "defimpl «Something», for: Atom do"
      assert decorate(doc, protocol.block_range) == expected_block
    end
  end
end
