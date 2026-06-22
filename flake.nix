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

        # FOD factory: online `gleam deps download` for a package `dir`. Output
        # = that package's resolved `<dir>/build/packages` tree (hex deps +
        # packages.toml). The hash is pinned to the package's manifest.toml
        # locked versions/checksums, so it only changes when the manifest
        # changes. `src` is the repo root so any local path dependency (e.g.
        # the server/client `shared` dep, ../shared) resolves.
        # `name` is passed explicitly (not derived from `dir`) so the server and
        # client FODs keep their original derivation names — and therefore their
        # original output store paths — leaving serverPkg/clientPkg/default
        # byte-for-byte identical to the pre-refactor flake. (FOD store paths are
        # computed from outputHash + name; renaming would force a re-download,
        # and `gleam deps download` writes packages.toml entries in a
        # non-deterministic order, so a fresh download can miss the pinned hash.)
        mkGleamDeps = name: dir: hash:
          pkgs.stdenvNoCC.mkDerivation {
            inherit name;
            src = ./.;
            nativeBuildInputs = [pkgs.gleam pkgs.cacert pkgs.git];
            buildPhase = ''
              export HOME=$TMPDIR
              (cd ${dir} && gleam deps download)
            '';
            installPhase = "cp -r ${dir}/build/packages $out";
            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
            outputHash = hash;
          };

        # Server deps FOD. server/manifest.toml resolves the wisp/mist/etc.
        # stack plus the local `shared` path dep.
        gleamDeps = mkGleamDeps "npwd-gleam-deps" "server" "sha256-fiY48olLJvFgMkZl6q0Ux3faJv5KTzd5TfT9RJM65Bk=";

        # Client deps FOD. client/manifest.toml is a separate manifest (target =
        # javascript; deps lustre/rsvp/modem/lustre_dev_tools), so it needs its
        # OWN resolved tree and OWN pinned hash, independent of the server.
        gleamClientDeps = mkGleamDeps "npwd-gleam-client-deps" "client" "sha256-IFgqWPgb3tfPX/G130qpN/a39yy9VEEOtQor42pzbGw=";

        # Shared deps FOD. shared/manifest.toml is a third manifest
        # (gleam_stdlib/gleam_json + gleeunit dev dep), needed so the `shared`
        # check can run gleam check + test offline.
        gleamSharedDeps = mkGleamDeps "npwd-gleam-shared-deps" "shared" "sha256-Du0zeZXBY0O9X6ban+e6ZOssb8YIW6MnVTg3rnSTqAY=";

        # Offline build: restore the pre-resolved deps into server/build/packages
        # and run `gleam export erlang-shipment` with no network. Output is the
        # erlang shipment tree ($out/entrypoint.sh + $out/<dep>/{ebin,priv}),
        # including $out/server/priv/static where Task 5 injects client.js.
        serverPkg = pkgs.stdenv.mkDerivation {
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
        clientPkg = pkgs.stdenv.mkDerivation {
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

        # Check factory for the no-DB packages (shared, client). Restores the
        # package's pre-resolved deps tree (so gleam runs OFFLINE, same pattern
        # as the build derivations above), then runs fmt + check + test.
        # `nodejs` is the default JavaScript test runtime, needed by the
        # client check (target = javascript); harmless for the erlang-target
        # shared check.
        mkGleamCheck = dir: depsFOD:
          pkgs.stdenv.mkDerivation {
            name = "npwd-check-${dir}";
            src = ./.;
            nativeBuildInputs = [pkgs.gleam pkgs.erlang_27 pkgs.rebar3 pkgs.nodejs];
            buildPhase = ''
              export HOME=$TMPDIR
              export REBAR_CACHE_DIR=$TMPDIR/.rebar-cache
              mkdir -p ${dir}/build
              cp -r ${depsFOD} ${dir}/build/packages
              chmod -R u+w ${dir}/build/packages
              cd ${dir}
              gleam format --check src test
              # `--warnings-as-errors` lives on `gleam build` (not `gleam check`)
              # in Gleam 1.17.0; build type-checks and fails on any warning.
              gleam build --warnings-as-errors
              gleam test
              touch $out
            '';
            phases = ["unpackPhase" "buildPhase"];
          };
      in {
        packages.server = serverPkg;

        packages.client = clientPkg;

        # The deployable artifact: the server erlang-shipment with
        # packages.client's client.js baked in at priv/static, so the
        # shipment serves the bundle without any manual copy step.
        packages.default = serverPkg.overrideAttrs (old: {
          postPatch =
            (old.postPatch or "")
            + "\ncp ${clientPkg}/client.js server/priv/static/client.js\n";
        });

        # fmt + `gleam build --warnings-as-errors` + tests per package, wired so
        # `nix flake check` runs them. shared/client need no database; server
        # needs SurrealDB, so it is Linux-only (loopback bind in the sandbox).
        checks.shared = mkGleamCheck "shared" gleamSharedDeps;
        checks.client = mkGleamCheck "client" gleamClientDeps;

        # Server check: start an in-memory SurrealDB on loopback, wait with a
        # BOUNDED readiness loop that exits non-zero on timeout (no fall-through),
        # then restore deps and run fmt + check + test offline.
        checks.server =
          pkgs.lib.mkIf pkgs.stdenv.isLinux
          (pkgs.stdenv.mkDerivation {
            name = "npwd-check-server";
            src = ./.;
            nativeBuildInputs = [
              pkgs.gleam
              pkgs.erlang_27
              pkgs.rebar3
              pkgs.surrealdb
              pkgs.curl
              pkgs.cacert
            ];
            buildPhase = ''
              export HOME=$TMPDIR
              export REBAR_CACHE_DIR=$TMPDIR/.rebar-cache
              # OTP 27 httpc eagerly loads OS CA certs even for plain-HTTP
              # requests, and pubkey_os_cacerts crashes (function_clause) when no
              # OS cert bundle exists, as in this sandbox. It honors the
              # public_key app env `cacerts_path`, so point that at the nixpkgs
              # cacert bundle. (The server reaches SurrealDB over httpc here.)
              export ERL_FLAGS="-public_key cacerts_path '\"${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt\"'"
              surreal start --user root --pass root \
                --bind 127.0.0.1:8001 memory &
              ready=0
              for _ in $(seq 1 30); do
                if curl -sf http://127.0.0.1:8001/health; then ready=1; break; fi
                sleep 1
              done
              if [ "$ready" -ne 1 ]; then
                echo "SurrealDB did not become ready" >&2
                exit 1
              fi
              mkdir -p server/build
              cp -r ${gleamDeps} server/build/packages
              chmod -R u+w server/build/packages
              cd server
              gleam format --check src test
              gleam build --warnings-as-errors
              gleam test
              touch $out
            '';
            phases = ["unpackPhase" "buildPhase"];
          });

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
