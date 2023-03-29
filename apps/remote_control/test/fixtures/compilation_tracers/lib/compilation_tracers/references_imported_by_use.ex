defmodule CompilationTracers.ReferencesImportedByUse do
  use CompilationTracers.ReferencesReferenced

  def uses_fun do
    referenced_fun()
  end

  def uses_macro(a) do
    referenced_macro a do
      :ok
    end
  end
end
