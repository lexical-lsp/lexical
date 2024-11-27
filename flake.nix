{
  description = "Reimagined language server for Elixir";

  inputs.nixpkgs.url = "flake:nixpkgs";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.systems.url = "github:nix-systems/default";

  outputs = {
    self,
    nixpkgs,
    systems,
    ...
  } @ inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      flake = {
        lib = {
          mkLexical = {erlang}: erlang.callPackage ./nix/lexical.nix {};
        };
      };

      systems = import systems;

      perSystem = {
        self',
        pkgs,
        ...
      }: let
        erlang = pkgs.beam.packages.erlang;
        lexical = self.lib.mkLexical {inherit erlang;};
      in {
        formatter = pkgs.alejandra;

        apps.update-hash = let
          script = pkgs.writeShellApplication {
            name = "update-hash";

            runtimeInputs = [pkgs.nixFlakes pkgs.gawk];

            text = ''
              nix --extra-experimental-features 'nix-command flakes' \
                build --no-link "${self}#__fodHashGen" 2>&1 | gawk '/got:/ { print $2 }' || true
            '';
          };
        in {
          type = "app";
          program = "${script}/bin/update-hash";
        };

        packages = {
          inherit lexical;
          default = lexical;

          __fodHashGen = lexical.mixFodDeps.overrideAttrs (final: curr: {
            outputHash = pkgs.lib.fakeSha256;
          });
        };

        devShells.default = pkgs.mkShell {
          packages =
            [
              erlang.elixir
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              pkgs.darwin.apple_sdk.frameworks.CoreFoundation
              pkgs.darwin.apple_sdk.frameworks.CoreServices
            ];
        };
      };
    };
}
