{
  mixRelease,
  fetchMixDeps,
  erlang,
  elixir,
}:
mixRelease rec {
  pname = "lexical";
  version = "development";

  src = ./..;

  mixFodDeps = fetchMixDeps {
    inherit pname;
    inherit version;

    src = ./..;

    sha256 = builtins.readFile ./hash;
  };

  installPhase = ''
    runHook preInstall

    mix do compile --no-deps-check, package --path "$out"

    runHook postInstall
  '';

  preFixup = ''
    for script in $out/releases/*/elixir; do
      substituteInPlace "$script" --replace 'ERL_EXEC="erl"' 'ERL_EXEC="${erlang}/bin/erl"'
    done

    substituteInPlace "$out/bin/start_lexical.sh" --replace 'elixir_command=' 'elixir_command="${elixir}/bin/"'

    makeWrapper $out/bin/start_lexical.sh $out/bin/lexical --set RELEASE_COOKIE lexical
  '';
}
