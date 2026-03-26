{
  description = "Elm OpenAPI CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;
        packageJson = builtins.fromJSON (builtins.readFile ./package.json);

        src = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [
            ./CHANGELOG.md
            ./LICENSE
            ./README.md
            ./bun.lock
            ./cli
            ./codegen
            ./docs
            ./elm.json
            ./helpers
            ./openapitools.json
            ./package.json
            ./review
            ./src
            ./tests
          ];
        };

        registryDat = ./cli/registry.dat;

        securityShim = pkgs.writeShellScriptBin "security" ''
          exec /usr/bin/security "$@"
        '';

        bunDeps = pkgs.stdenvNoCC.mkDerivation {
          pname = "${packageJson.name}-bun-deps";
          version = packageJson.version;
          inherit src;

          nativeBuildInputs = [
            pkgs.bun
            pkgs.nodejs_20
            pkgs.writableTmpDirAsHomeHook
          ];

          dontConfigure = true;

          buildPhase = ''
            runHook preBuild

            export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
            bun install --frozen-lockfile --no-progress

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out
            cp -R node_modules $out/

            runHook postInstall
          '';

          dontFixup = true;
          outputHash = "sha256-fl59fFEyLAdAZynW3o0YR+YexLPMn7mYKw8EM/LB0IE=";
          outputHashAlgo = "sha256";
          outputHashMode = "recursive";
        };

        elmOpenApi = pkgs.stdenv.mkDerivation {
          pname = packageJson.name;
          version = packageJson.version;
          inherit src;
          __impureHostDeps = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
            "/bin/sh"
            "/usr/bin/security"
          ];

          nativeBuildInputs = [
            pkgs.bash
            pkgs.bun
            pkgs.curl
            pkgs.elmPackages.elm
            pkgs.git
            pkgs.nodejs_20
            pkgs.writableTmpDirAsHomeHook
            securityShim
          ];

          configurePhase =
            (pkgs.elmPackages.fetchElmDeps {
              elmPackages = import ./cli/elm-srcs.nix;
              elmVersion = pkgs.elmPackages.elm.version;
              inherit registryDat;
            })
            + ''
              cp -R ${bunDeps}/node_modules .
              chmod -R +w node_modules
              ln -sf ${lib.getExe pkgs.elmPackages.elm} node_modules/.bin/elm
            '';

          buildPhase = ''
            runHook preBuild

            export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
            bun run build

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            install -Dm755 dist/elm-open-api.js "$out/bin/elm-open-api"

            runHook postInstall
          '';

          meta = {
            description = packageJson.description;
            homepage = "https://github.com/wolfadex/elm-open-api-cli";
            license = lib.licenses.mit;
            mainProgram = "elm-open-api";
            platforms = lib.platforms.unix;
          };
        };
      in
      {
        packages.default = elmOpenApi;
        packages.elm-open-api = elmOpenApi;
        apps.default = flake-utils.lib.mkApp { drv = elmOpenApi; };
        devShells.default = import ./shell.nix { inherit pkgs; };
      }
    );
}
