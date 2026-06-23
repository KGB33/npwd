{
  description = "NPWD - New Page Who's This?";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-gleam = {
      url = "github:arnarg/nix-gleam";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {system, ...}: let
        pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [inputs.nix-gleam.overlays.default];
          config.allowUnfreePredicate = pkg:
            builtins.elem (inputs.nixpkgs.lib.getName pkg) ["surrealdb"];
        };

        inherit (pkgs) buildGleamApplication;

        server = buildGleamApplication {
          src = ./server;
          localPackages = [./shared];
        };

        client = buildGleamApplication {
          src = ./client;
          localPackages = [./shared];
          nativeBuildInputs = with pkgs; [bun erlang rebar3];
          buildPhase = ''
            runHook preBuild
            export HOME=$TMPDIR
            gleam run -m lustre/dev build --minify --outdir=build/static
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            install -Dm644 build/static/client.js $out/client.js
            runHook postInstall
          '';
        };

        npwd = server.overrideAttrs (old: {
          pname = "npwd";
          preBuild =
            (old.preBuild or "")
            + ''
              cp ${client}/client.js priv/static/client.js
            '';
        });

        mkCheck = {
          pkg,
          extraInputs ? [],
          preTest ? "",
        }:
          pkg.overrideAttrs (old: {
            pname = "${old.pname or "gleam"}-check";
            nativeBuildInputs = old.nativeBuildInputs ++ extraInputs;
            buildPhase = ''
              runHook preBuild
              export HOME=$TMPDIR
              export REBAR_CACHE_DIR=$TMPDIR/.rebar-cache
              ${preTest}
              gleam format --check src test
              gleam check
              gleam test
              runHook postBuild
            '';
            installPhase = "touch $out";
            dontFixup = true;
          });

        sharedCheck = mkCheck {
          pkg = buildGleamApplication {src = ./shared;};
        };

        clientCheck = mkCheck {
          pkg = client;
        };
      in {
        packages = {
          inherit client npwd;
          default = npwd;
        };

        checks =
          {
            shared = sharedCheck;
            client = clientCheck;
          }
          // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
            server = mkCheck {
              pkg = server;
              extraInputs = with pkgs; [surrealdb curl cacert];
              preTest = ''
                # OTP's httpc eagerly loads OS CA certs and crashes when none
                # exist (as in the sandbox); point public_key at the nixpkgs CA
                # bundle so plain-HTTP requests to SurrealDB don't trip it.
                export ERL_FLAGS="-public_key cacerts_path '\"${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt\"'"
                surreal start --user root --pass root --bind 127.0.0.1:8001 memory &
                ready=0
                for _ in $(seq 1 30); do
                  if curl -sf http://127.0.0.1:8001/health; then
                    ready=1
                    break
                  fi
                  sleep 1
                done
                if [ "$ready" -ne 1 ]; then
                  echo "SurrealDB did not become ready" >&2
                  exit 1
                fi
              '';
            };
          };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            gleam
            erlang
            rebar3
            bun
            surrealdb
          ];
        };
      };
    };
}
