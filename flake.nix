{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devenv.url = "github:cachix/devenv";
    github-actions-nix.url = "github:synapdeck/github-actions-nix";
    nix-gleam = {
      url = "github:arnarg/nix-gleam";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.devenv.flakeModule
        inputs.github-actions-nix.flakeModule
      ];
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {
        config,
        self',
        inputs',
        pkgs,
        system,
        ...
      }: let
        buildGleamApplication = inputs'.nix-gleam.packages.buildGleamApplication;
      in {
        devenv = {
          shells.default = {
            packages = with pkgs; [
              beam28Packages.erlang
              gleam
              rebar3
              bun
            ];
            env = {
            };
            services.postgres = {
              enable = true;
              package = pkgs.postgresql_18;
              listen_addresses = "localhost";
              settings.max_connections = 200;
              initialDatabases =
                ["dev" "test"]
                |> map (db: {
                  name = db;
                  initialSQL = builtins.readFile ./schema.sql;
                });
            };
          };
        };
        packages = {
          workflows = pkgs.writeShellApplication {
            name = "copy-workflows";
            text = ''
              cp -r ${config.githubActions.workflowsDir}/. ./.github/workflows
              chmod -R u+w ./.github/workflows
            '';
          };

          client = buildGleamApplication {
            src = ./client;
            localPackages = [./shared];
            target = "erlang";
            nativeBuildInputs = [pkgs.bun];
            buildPhase = ''
              runHook preBuild
              export REBAR_CACHE_DIR="$TMP/.rebar-cache"
              gleam run -m lustre/dev build --minify --outdir=./out
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out
              cp out/client.js $out/client.js
              runHook postInstall
            '';
          };

          server = buildGleamApplication {
            src = ./server;
            localPackages = [./shared];
            erlangPackage = pkgs.beam28Packages.erlang;
            rebar3Package = pkgs.beam28Packages.rebar3WithPlugins {
              plugins = with pkgs.beam28Packages; [pc];
            };
            preConfigure = ''
              cp ${self'.packages.client}/client.js priv/static/client.js
            '';
          };

          npwd = pkgs.writeShellScriptBin "npwd" ''
            exec ${self'.packages.server}/bin/server "$@"
          '';
        };
        githubActions = {
          enable = true;
          workflows = let
            checkoutStep = {
              uses = "actions/checkout@v4";
            };
            checkSteps = [
              {
                run = "gleam deps download";
              }
              {
                run = "gleam test";
              }
              {
                run = "gleam format --check src test";
              }
            ];

            beamSetupStep = {
              uses = "erlef/setup-beam@v1";
              with_ = {
                otp-version = "28";
                gleam-version = "1.14.0";
                rebar3-version = "3";
              };
            };
            mkTest = dir: setupStep: {
              name = "Unit test ${dir}";
              on = ["push" "pull_request"];
              defaults.run.workingDirectory = "./${dir}";
              jobs = {
                test = {
                  runsOn = "ubuntu-latest";
                  steps =
                    [
                      checkoutStep
                      setupStep
                    ]
                    ++ checkSteps;
                };
              };
            };
            mkJsTest = dir: {};
          in {
            testServer = mkTest "server" beamSetupStep;
            testSharedBeam = mkTest "shared" beamSetupStep;
          };
        };
      };
      flake = {};
    };
}
