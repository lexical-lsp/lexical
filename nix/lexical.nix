{
  mixRelease,
  fetchMixDeps,
  elixir,
  writeScript,
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

  preFixup = let
    activate_version_manager = writeScript "activate_version_manager.sh" ''
    true
    '';
  in ''
    substituteInPlace "$out/bin/start_lexical.sh" --replace 'elixir_command=' 'elixir_command="${elixir}/bin/"'
    rm "$out/bin/activate_version_manager.sh"
    ln -s ${activate_version_manager} "$out/bin/activate_version_manager.sh"

    mv "$out/bin" "$out/binsh"

    makeWrapper "$out/binsh/start_lexical.sh" "$out/bin/lexical" --set RELEASE_COOKIE lexical
  '';
}
