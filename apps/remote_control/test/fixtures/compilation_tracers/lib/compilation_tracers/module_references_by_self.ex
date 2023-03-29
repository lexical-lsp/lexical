defmodule CompilationTracers.ModuleReferencesBySelf1 do
  __MODULE__
end

defmodule CompilationTracers.ModuleReferencesBySelf2 do
  __MODULE__
end

defmodule CompilationTracers.ModuleReferencesBySelf3 do
  defmodule Child.Some do
    __MODULE__
  end
end
