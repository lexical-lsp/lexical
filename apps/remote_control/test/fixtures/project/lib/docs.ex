defmodule Project.Docs do
  defmodule PublicModule do
    @moduledoc """
    This module has docs.
    """

    @typedoc "type docs for my_type"
    @type my_type :: :ok

    @typedoc "type docs for my_opaque"
    @opaque my_opaque :: :ok

    @doc """
    Docs for `fun/0`.

        iex> Project.Docs.PublicModule.fun()
        :ok
    """
    def fun, do: :ok

    @doc """
    Docs for `fun/1`.

        iex> Project.Docs.PublicModule.fun(1)
        :ok
    """
    def fun(_), do: :ok

    @doc """
    Docs for `fun/2`.

        iex> Project.Docs.PublicModule.fun(1, 2)
        :ok
    """
    def fun(_, _), do: :ok
  end

  defmodule PrivateModule do
    @moduledoc false

    @typedoc false
    @type my_type :: :ok

    @typedoc false
    @opaque my_opaque :: :ok

    @doc false
    def fun, do: :ok

    @doc false
    def fun(_), do: :ok

    @doc false
    def fun(_, _), do: :ok
  end

  defmodule UndocumentedModule do
    @type my_type :: :ok
    @opaque my_opaque :: :ok
    def fun, do: :ok
    def fun(_), do: :ok
    def fun(_, _), do: :ok
  end

  alias Project.Docs.PublicModule
  @type t1 :: PublicModule.my_type()
  @type t2 :: PublicModule.my_opaque()
  PublicModule.fun()

  alias Project.Docs.PrivateModule
  @type t3 :: PrivateModule.my_type()
  @type t4 :: PrivateModule.my_opaque()
  PrivateModule.fun()

  alias Project.Docs.UndocumentedModule
  @type t5 :: UndocumentedModule.my_type()
  @type t6 :: UndocumentedModule.my_opaque()
  UndocumentedModule.fun()
end
