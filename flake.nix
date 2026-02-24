{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devenv.url = "github:cachix/devenv";
    github-actions-nix.url = "github:synapdeck/github-actions-nix";
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
      }: {
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
              cp -r ${config.githubActions.workflowsDir} ./.github/workflows
              chmod -R u+w ./.github/workflows
            '';
          };
        };
        githubActions = {
          enable = true;
          workflows = let
          in {
            testServer = {
              name = "Unit test server";
              on = ["push" "pull_request"];
              defaults.run.workingDirectory = "./server";
              jobs = {
                test = {
                  runsOn = "ubuntu-latest";
                  steps = [
                    {
                      uses = "actions/checkout@v4";
                    }
                    {
                      uses = "erlef/setup-beam@v1";
                      with_ = {
                        otp-version = "28";
                        gleam-version = "1.14.0";
                        rebar3-version = "3";
                      };
                    }
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
                };
              };
            };
          };
        };
      };
      flake = {};
    };
}
