{
  description = "NPWD - New Page Who's This?";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {system, ...}: let
        pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg:
            builtins.elem (inputs.nixpkgs.lib.getName pkg) ["surrealdb"];
        };
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            gleam
            erlang_27
            rebar3
            nodejs
            bun
            surrealdb
          ];
          shellHook = ''
            export SURREAL_HOST=127.0.0.1
            export SURREAL_PORT=8000
            export SURREAL_NAMESPACE=npwd
            export SURREAL_DATABASE=npwd
            export SURREAL_USER=root
            export SURREAL_PASSWORD=root
            export PORT=3000
            export SECRET_KEY_BASE=dev-only-secret-key-base-change-in-prod
          '';
        };
      };
    };
}
