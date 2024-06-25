defmodule Lexical.Server.CodeIntelligence.CompletionTest do
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Protocol.Types.Completion.Item, as: CompletionItem
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.SortScope

  use Lexical.Test.Server.CompletionCase
  use Patch

  describe "excluding modules from lexical dependencies" do
    test "lexical modules are removed", %{project: project} do
      assert [] = complete(project, "Lexica|l")
    end

    test "Lexical submodules are removed", %{project: project} do
      assert [] = complete(project, "Lexical.RemoteContro|l")
    end

    test "Lexical functions are removed", %{project: project} do
      assert [] = complete(project, "Lexical.RemoteControl.|")
    end

    test "Dependency modules are removed", %{project: project} do
      assert [] = complete(project, "ElixirSense|")
    end

    test "Dependency functions are removed", %{project: project} do
      assert [] = complete(project, "Jason.encod|")
    end

    test "Dependency protocols are removed", %{project: project} do
      assert [] = complete(project, "Jason.Encode|")
    end

    test "Dependency structs are removed", %{project: project} do
      assert [] = complete(project, "Jason.Fragment|")
    end

    test "Dependency exceptions are removed", %{project: project} do
      assert [] = complete(project, "Jason.DecodeErro|")
    end
  end

  test "ensure completion works for project", %{project: project} do
    refute [] == complete(project, "Project.|")
  end

  describe "single character atom completions" do
    test "complete elixir modules", %{project: project} do
      assert [_ | _] = completions = complete(project, "E|")

      for completion <- completions do
        assert completion.kind == :module
      end
    end

    test "ignore erlang modules", %{project: project} do
      assert [] == complete(project, ":e|")
    end
  end

  describe "ignoring things" do
    test "returns an incomplete completion list when the context is empty", %{project: project} do
      assert %Completion.List{is_incomplete: true, items: []} =
               complete(project, " ", as_list: false)
    end

    test "returns no completions in a comment at the beginning of a line", %{project: project} do
      assert [] == complete(project, "# IO.in|")
    end

    test "returns no completions in a comment at the end of a line", %{project: project} do
      assert [] == complete(project, "IO.inspe # IO.in|")
    end

    test "returns no completions in double quoted strings", %{project: project} do
      assert [] = complete(project, ~S/"IO.in|"/)
    end

    test "returns no completions inside heredocs", %{project: project} do
      assert [] = complete(project, ~S/
      """
      This is my heredoc
      It does not IO.in|
      """
     /)
    end

    test "returns no completions inside ~s", %{project: project} do
      assert [] = complete(project, ~S/~s[ IO.in|]/)
    end

    test "returns no completions inside ~S", %{project: project} do
      assert [] = complete(project, ~S/ ~S[ IO.in|] /)
    end

    test "only modules that are behaviuors are completed in an @impl", %{project: project} do
      assert [behaviour] = complete(project, "@impl U|")
      assert behaviour.label == "Unary"
      assert behaviour.kind == :module
    end
  end

  describe "do/end" do
    test "returns do/end when the last token is 'do'", %{project: project} do
      assert [completion] = complete(project, "for a <- something do|")
      assert completion.label == "do/end block"
    end

    test "returns do/end when the last token is 'd'", %{project: project} do
      assert [completion] = complete(project, "for a <- something d|")
      assert completion.label == "do/end block"
    end
  end

  describe "sorting dunder function/macro completions" do
    test "dunder functions are sorted last in their sort scope", %{project: project} do
      {:ok, completion} =
        project
        |> complete("Enum.|")
        |> fetch_completion("__info__")

      %CompletionItem{
        sort_text: sort_text
      } = completion

      assert sort_text =~ SortScope.remote(false, 9)
    end

    test "dunder macros are sorted last in their scope", %{project: project} do
      {:ok, completion} =
        project
        |> complete("Project.__dunder_macro__|")
        |> fetch_completion("__dunder_macro__")

      %CompletionItem{
        sort_text: sort_text
      } = completion

      assert sort_text =~ SortScope.remote(false, 9)
    end

    test "typespecs with no origin are completed", %{project: project} do
      candidate = %Candidate.Typespec{
        argument_names: [],
        metadata: %{builtin: true},
        arity: 0,
        name: "any",
        origin: nil
      }

      patch(Lexical.RemoteControl.Api, :complete, [candidate])

      [completion] = complete(project, " @type a|")
      assert completion.label == "any()"
    end

    test "typespecs with no full_name are completed", %{project: project} do
      candidate = %Candidate.Struct{full_name: nil, metadata: %{}, name: "Struct"}
      patch(Lexical.RemoteControl.Api, :complete, [candidate])

      [completion] = complete(project, " %Stru|")
      assert completion.label == "Struct"
    end
  end

  def with_all_completion_candidates(_) do
    name = "Foo"
    full_name = "A.B.Foo"

    all_completions = [
      %Candidate.Behaviour{name: "#{name}-behaviour", full_name: full_name},
      %Candidate.BitstringOption{name: "#{name}-bitstring", type: "integer"},
      %Candidate.Callback{
        name: "#{name}-callback",
        origin: full_name,
        argument_names: [],
        metadata: %{},
        arity: 0
      },
      %Candidate.Exception{name: "#{name}-exception", full_name: full_name},
      %Candidate.Function{
        name: "my_func",
        origin: full_name,
        argument_names: [],
        metadata: %{},
        arity: 0
      },
      %Candidate.Macro{
        name: "my_macro",
        origin: full_name,
        argument_names: [],
        metadata: %{},
        arity: 0
      },
      %Candidate.MixTask{name: "#{name}-mix-task", full_name: full_name},
      %Candidate.Module{name: "#{name}-module", full_name: full_name},
      %Candidate.Module{name: "#{name}-submodule", full_name: "#{full_name}.Bar"},
      %Candidate.ModuleAttribute{name: "#{name}-module-attribute"},
      %Candidate.Protocol{name: "#{name}-protocol", full_name: full_name},
      %Candidate.Struct{name: "#{name}-struct", full_name: full_name},
      %Candidate.StructField{name: "#{name}-struct-field", origin: full_name},
      %Candidate.Typespec{
        name: "#{name}-typespec",
        origin: full_name,
        argument_names: ["value"],
        arity: 1,
        metadata: %{}
      },
      %Candidate.Variable{name: "#{name}-variable"}
    ]

    patch(Lexical.RemoteControl.Api, :complete, all_completions)
    :ok
  end

  describe "context aware inclusions and exclusions" do
    setup [:with_all_completion_candidates]

    test "only modules and module-like completions are returned in an alias", %{project: project} do
      completions = complete(project, "alias Foo.")

      for completion <- complete(project, "alias Foo.") do
        assert %_{kind: :module} = completion
      end

      assert {:ok, _} = fetch_completion(completions, label: "Foo-behaviour")
      assert {:ok, _} = fetch_completion(completions, label: "Foo-module")
      assert {:ok, _} = fetch_completion(completions, label: "Foo-protocol")
      assert {:ok, _} = fetch_completion(completions, label: "Foo-struct")
    end

    test "only modules, typespecs and module attributes are returned in types", %{
      project: project
    } do
      completions =
        for completion <- complete(project, "@spec F"), into: MapSet.new() do
          completion.label
        end

      assert "Foo-module" in completions
      assert "Foo-module-attribute" in completions
      assert "Foo-submodule" in completions
      assert "Foo-typespec(value)" in completions
      assert Enum.count(completions) == 4
    end

    test "modules are sorted before functions", %{project: project} do
      code = ~q[
        def in_function do
          Foo.|
        end
      ]

      completions =
        project
        |> complete(code)
        |> Enum.sort_by(& &1.sort_text)

      module_index = Enum.find_index(completions, &(&1.label == "Foo-module"))
      behaviour_index = Enum.find_index(completions, &(&1.label == "Foo-behaviour"))
      submodule_index = Enum.find_index(completions, &(&1.label == "Foo-submodule"))

      function_index = Enum.find_index(completions, &(&1.label == "my_function()"))
      macro_index = Enum.find_index(completions, &(&1.label == "my_macro()"))
      callback_index = Enum.find_index(completions, &(&1.label == "Foo-callback()"))

      assert submodule_index < function_index
      assert submodule_index < macro_index
      assert submodule_index < callback_index

      assert module_index < function_index
      assert module_index < macro_index
      assert module_index < callback_index

      assert behaviour_index < function_index
      assert behaviour_index < macro_index
      assert behaviour_index < callback_index
    end
  end
end
