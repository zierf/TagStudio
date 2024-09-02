{
  description = "TagStudio";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    supportedSystems.url = "github:nix-systems/default-linux";

    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, poetry2nix, ... } @inputs:
    let
      # see examples for Nix Flake template and basic usage for nix-systems
      # https://github.com/nix-systems/nix-systems?tab=readme-ov-file#basic-usage
      # https://github.com/NixOS/templates/blob/master/python/flake.nix
      eachSystem = nixpkgs.lib.genAttrs (import inputs.supportedSystems);

      pkgs = eachSystem (system: nixpkgs.legacyPackages.${system}.extend poetry2nix.overlays.default);

      mkPoetryApplication = eachSystem (system: (poetry2nix.lib.mkPoetry2Nix { pkgs = pkgs.${system}; }).mkPoetryApplication);
      defaultPoetryOverrides = eachSystem (system: (poetry2nix.lib.mkPoetry2Nix { pkgs = pkgs.${system}; }).defaultPoetryOverrides);

      tagstudioApp = eachSystem (system:
        mkPoetryApplication.${system} rec {
          projectDir = self;

          exeName = "tagstudio";

          python = pkgs.${system}.python312;
          dontWrapQtApps = false;

          # preferWheels to resolve typing stubs error for opencv-python:
          #   'Failed to resolve alias "GProtoArg" exposed as "GProtoArg"'
          # https://github.com/opencv/opencv-python/issues/1010
          preferWheels = true;

          # extend official overrides
          # https://github.com/nix-community/poetry2nix/blob/7619e43c2b48c29e24b88a415256f09df96ec276/overrides/default.nix#L2743-L2805
          overrides = defaultPoetryOverrides.${system}.extend (final: prev: {
            # Overrides for PySide6
            # https://github.com/nix-community/poetry2nix/issues/1191#issuecomment-1707590287
            pyside6 = final.pkgs.python312.pkgs.pyside6;
            #shiboken6 = final.pkgs.python3.pkgs.shiboken6;
          });

          pythonRelaxDeps = [ ];

          dependencies = (with pkgs.${system}; [
            dbus
            fontconfig
            freetype
            glib
            libGL
            libkrb5
            libpulseaudio
            libva
            libxkbcommon
            openssl
            stdenv.cc.cc.lib
            wayland
            xorg.libX11
            xorg.libxcb
            xorg.libXi
            xorg.libXrandr
            # `qt6.full` prevents error with different QT version on KDE systems:
            #   'Cannot mix incompatible Qt library (6.7.2) with this library (6.7.1)'
            qt6.full
          ]);

          buildInputs = (with pkgs.${system}; [
            qt6.qtbase
          ]) ++ dependencies;

          nativeBuildInputs = (with pkgs.${system}; [
            copyDesktopItems
            makeWrapper
            qt6.wrapQtAppsHook
          ])
          ++ dependencies;

          propogatedBuildInputs = (with pkgs.${system}; [ ]) ++ dependencies;

          # libraryPath = pkgs.${system}.lib.makeLibraryPath ((with pkgs.${system}; [
          #   "$out"
          # ]) ++ dependencies);

          # binaryPath = pkgs.${system}.lib.makeBinPath ((with pkgs.${system}; [
          #   "$out"
          # ]) ++ dependencies);

          desktopItems = [
            (pkgs.${system}.makeDesktopItem {
              name = "TagStudio";
              desktopName = "TagStudio";
              comment = "A User-Focused Document Management System";
              categories = [ "AudioVideo" "Utility" "Qt" "Development" ];
              exec = "${exeName} %U";
              icon = "${exeName}";
              terminal = false;
              type = "Application";
            })
          ];

          preInstall = ''
            mkdir -p $out/share/icons/hicolor/256x256/apps
            cp -rv ${projectDir}/tagstudio/resources/icon.png $out/share/icons/hicolor/256x256/apps/${exeName}.png
          '';
        }
      );
    in
    {
      # apps = eachSystem (system: {
      #   # $> nix run
      #   default = {
      #     type = "app";
      #     # name in [tool.poetry.scripts] section of pyproject.toml
      #     program = "${tagstudioApp."${system}"}/bin/${tagstudioApp."${system}".exeName}";
      #   };
      # });

      packages = eachSystem (system: {
        # $> nix run tagstudio
        tagstudio = tagstudioApp.${system};
        # $> nix run
        default = tagstudioApp.${system};
      });

      devShells = eachSystem (system: {
        # Development Shell including `poetry`.
        # $> nix develop
        #
        # Use this shell for developing the application and
        # making changes to `pyproject.toml` and `poetry.lock` files.
        #
        # $> poetry install                   => install packages stated by petry.lock file
        # $> poetry lock                      => update lock file after changing dependencies
        # $> python ./tagstudio/tag_studio.py => launch application via Python
        # $> poetry run tagstudio             => execute the application via Poetry
        default = pkgs.${system}.mkShell rec {
          #inputsFrom = [ self.apps.${system}.default ];
          inputsFrom = [ self.packages.${system}.tagstudio ];

          packages = with pkgs.${system}; [
            poetry
            cmake
            mypy
            ruff
          ] ++ (with pkgs.${system}; [
            qtcreator
          ])
          ++ tagstudioApp.${system}.dependencies;

          LD_LIBRARY_PATH = pkgs.${system}.lib.makeLibraryPath packages;
        };

        # Shell for poetry.
        #
        # Needed to create first lock file.
        # $> nix develop .#poetry
        # $> poetry install
        #
        # Use this shell for changes to pyproject.toml and poetry.lock.
        devShells.poetry = pkgs.mkShell {
          packages = [ pkgs.poetry ];
        };
      });
    };
}
