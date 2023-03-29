defmodule CompilationTracers.ReferencesAlias do
  require CompilationTracers.ReferencesReferenced, as: ReferencesReferenced
  alias CompilationTracers.ReferencesReferenced, as: Some
  alias Some, as: Other
  import Other

  def uses_alias_1 do
    ReferencesReferenced
  end

  def uses_alias_2 do
    Some
  end

  def uses_alias_3 do
    CompilationTracers.ReferencesReferenced
  end

  def uses_alias_4 do
    uses_attribute()
    Other
  end

  def uses_alias_5_func do
    ReferencesReferenced.referenced_fun()
  end
end
