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

        # ---------------------------------------------------------------------
        # Build mechanism: FOD (fixed-output derivation), NOT nix-gleam.
        #
        # Decision (Task 3 spike): arnarg/nix-gleam's `buildGleamApplication`
        # does not work with Gleam 1.17.0. Gleam 1.17 always re-runs "Resolving
        # versions" and contacts repo.hex.pm during the build phase, even when
        # `build/packages/packages.toml` and the hex package cache are present
        # (which is all nix-gleam pre-seeds). That fails in the sandbox with
        # `No CA certificates / error sending request for url`.
        #
        # The only reliable offline recipe with 1.17.0: run `gleam deps
        # download` ONCE with network (the FOD `gleamDeps` below), capture the
        # resulting `server/build/packages` tree (resolved deps + packages.toml),
        # then in the sealed build restore that tree and run `gleam export
        # erlang-shipment` with NO network. The captured packages tree carries
        # the resolution metadata that suppresses any further hex contact.
        #
        # Tasks 5 (packages.default) and 6 (checks) MUST reuse `gleamDeps` and
        # this same "restore build/packages, then build/export offline" pattern.
        # ---------------------------------------------------------------------

        # FOD: online `gleam deps download`. Output = the resolved
        # `server/build/packages` tree (hex deps + packages.toml). The hash is
        # pinned to manifest.toml's locked versions/checksums, so it only
        # changes when the manifests change. `src` is the repo root so the
        # `shared` local path dependency (../shared) resolves.
        gleamDeps = pkgs.stdenvNoCC.mkDerivation {
          name = "npwd-gleam-deps";
          src = ./.;
          nativeBuildInputs = [pkgs.gleam pkgs.cacert pkgs.git];
          buildPhase = ''
            export HOME=$TMPDIR
            (cd server && gleam deps download)
          '';
          installPhase = "cp -r server/build/packages $out";
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-fiY48olLJvFgMkZl6q0Ux3faJv5KTzd5TfT9RJM65Bk=";
        };

        # FOD for the CLIENT package. client/manifest.toml is a separate
        # manifest (target = javascript; deps lustre/rsvp/modem/lustre_dev_tools),
        # so it needs its OWN resolved build/packages tree and its OWN pinned
        # hash, independent of the server's gleamDeps above.
        gleamClientDeps = pkgs.stdenvNoCC.mkDerivation {
          name = "npwd-gleam-client-deps";
          src = ./.;
          nativeBuildInputs = [pkgs.gleam pkgs.cacert pkgs.git];
          buildPhase = ''
            export HOME=$TMPDIR
            (cd client && gleam deps download)
          '';
          installPhase = "cp -r client/build/packages $out";
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-IFgqWPgb3tfPX/G130qpN/a39yy9VEEOtQor42pzbGw=";
        };
      in {
        # Offline build: restore the pre-resolved deps into server/build/packages
        # and run `gleam export erlang-shipment` with no network. Output is the
        # erlang shipment tree ($out/entrypoint.sh + $out/<dep>/{ebin,priv}),
        # including $out/server/priv/static where Task 5 injects client.js.
        packages.server = pkgs.stdenv.mkDerivation {
          name = "npwd-server";
          src = ./.;
          nativeBuildInputs = [pkgs.gleam pkgs.erlang_27 pkgs.rebar3];
          buildPhase = ''
            export HOME=$TMPDIR
            export REBAR_CACHE_DIR=$TMPDIR/.rebar-cache
            mkdir -p server/build
            cp -r ${gleamDeps} server/build/packages
            chmod -R u+w server/build/packages
            (cd server && gleam export erlang-shipment)
          '';
          installPhase = "cp -r server/build/erlang-shipment $out";
        };

        # Offline build: restore the pre-resolved client deps into
        # client/build/packages, then bundle the Lustre app with `gleam run -m
        # lustre/dev build`. client/gleam.toml sets `bun = "system"` so the
        # nixpkgs bun (on PATH) is used instead of a downloaded prebuilt. Output
        # is $out/client.js, which Task 5 injects into the server shipment.
        packages.client = pkgs.stdenv.mkDerivation {
          name = "npwd-client";
          src = ./.;
          nativeBuildInputs = [pkgs.gleam pkgs.bun pkgs.erlang_27 pkgs.rebar3];
          buildPhase = ''
            export HOME=$TMPDIR
            mkdir -p client/build
            cp -r ${gleamClientDeps} client/build/packages
            chmod -R u+w client/build/packages
            (cd client && gleam run -m lustre/dev build --outdir=build/static)
          '';
          installPhase = "install -Dm644 client/build/static/client.js $out/client.js";
        };

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
