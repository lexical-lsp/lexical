defmodule Lexical.RemoteControl.Search.Indexer.StructureTest do
  use Lexical.Test.ExtractorCase

  def index(source) do
    case do_index(source, fn entry -> entry.type != :metadata end) do
      {:ok, results, _doc} -> {:ok, results}
      error -> error
    end
  end

  describe "blocks are correctly popped " do
    test "when multiple blocks end at once" do
      {:ok, results} =
        ~q[
          def function_1 do
            case something() do
              :ok -> :yep
              _ -> :nope
            end
          end

          defp function_2 do
          end
        ]
        |> index()

      [public_function, private_function] =
        Enum.filter(results, fn entry ->
          entry.subtype == :definition
        end)

      assert public_function.block_id == :root
      assert private_function.block_id == :root
    end

    test "when an expression occurs after a block" do
      {:ok, [first_call, _, last_call]} =
        ~q[
          first_call()
          case something() do
            :ok -> :yep
            _ -> :nope
          end
          call()
        ]
        |> index()

      assert first_call.block_id == :root
      assert last_call.block_id == :root
    end
  end
end
