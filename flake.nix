{
  description = "Plataforma Centralizada de Qualidade, Normalização e Gestão de Dados - SETIC/CAGD";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      systems,
      pyproject-nix,
      git-hooks,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import systems;
      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          system,
          ...
        }:
        let
          pyproject = builtins.fromTOML (builtins.readFile ./pyproject.toml);
          _ = pyproject-nix.lib.project.loadPyproject { projectRoot = ./.; };

          pre-commit-check = git-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              # Formatters
              ruff-format.enable = true;

              # Linters & Static Analysis
              ruff.enable = true;

              # Hygiene
              trim-trailing-whitespace.enable = true;
              end-of-file-fixer.enable = true;
            };
          };
        in
        {
          _module.args.pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          checks = {
            inherit pre-commit-check;
            package = self'.packages.default;
          };

          packages.default =
            with pkgs;
            stdenv.mkDerivation {
              pname = pyproject.project.name;
              version = pyproject.project.version;
              src = ./.;
              nativeBuildInputs = [
                python3
                uv
                pkg-config
                gcc
              ];
              buildPhase = "true";
              installPhase = ''
                mkdir -p $out/lib
                cp -r backend frontend pyproject.toml $out/lib/
              '';
            };

          devShells.default =
            with pkgs;
            mkShell {
              name = "${pyproject.project.name}-devshell";

              packages =
                [
                  python3
                  uv
                  pyright
                  podman-compose
                ]
                ++ pre-commit-check.enabledPackages;

              env = {
                DATABASE_URL = "postgresql+psycopg://postgres:postgres@localhost:5432/setic_qualidade";
                LD_LIBRARY_PATH = lib.makeLibraryPath [
                  stdenv.cc.cc.lib
                  zlib
                ];
              };

              shellHook = ''
                ${pre-commit-check.shellHook}
                [ -d ".venv" ] && export PATH="$PWD/.venv/bin:$PATH" && export VIRTUAL_ENV="$PWD/.venv"
              '';
            };
        };
    };
}
