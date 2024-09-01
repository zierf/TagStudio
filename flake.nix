{
  description = "TagStudio";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Pinned to Qt version 6.7.1
    # nixpkgs-qt6.url = "github:NixOS/nixpkgs/e6cea36f83499eb4e9cd184c8a8e823296b50ad5";

    supportedSystems.url = "github:nix-systems/default-linux";

    poetry2nix.url = "github:nix-community/poetry2nix";
  };

  outputs = { self, nixpkgs, flake-utils, poetry2nix, ... } @inputs:
    # TODO https://github.com/NixOS/templates/blob/master/python/flake.nix
    let
      # see examples for Nix Flake template and basic usage for nix-systems
      # https://github.com/nix-systems/nix-systems?tab=readme-ov-file#basic-usage
      # https://github.com/NixOS/templates/blob/master/python/flake.nix
      eachSystem = nixpkgs.lib.genAttrs (import inputs.supportedSystems);

      pkgs = eachSystem (system: nixpkgs.legacyPackages.${system}.extend poetry2nix.overlays.default);
      #qt6Pkgs = eachSystem (system: import inputs.nixpkgs-qt6 { inherit system; });

      # override some missing dependencies for python packages
      # https://github.com/nix-community/poetry2nix/blob/8ffbc64abe7f432882cb5d96941c39103622ae5e/docs/edgecases.md#modulenotfounderror-no-module-named-packagename
      pypkgs-build-requirements = {
        #pyside6 = [ "pyside6-addons" "pyside6-essentials" ];
      };

      p2n-overrides = eachSystem (system:
        pkgs.${system}.poetry2nix.defaultPoetryOverrides.extend (self: super:
          builtins.mapAttrs
            (package: build-requirements:
              (builtins.getAttr package super).overridePythonAttrs (old: {
                buildInputs = (old.buildInputs or [ ]) ++ (builtins.map (pkg: if builtins.isString pkg then builtins.getAttr pkg super else pkg) build-requirements);
              })
            )
            pypkgs-build-requirements
        )
      );

      mkPoetryApplication = eachSystem (system: (poetry2nix.lib.mkPoetry2Nix { pkgs = pkgs.${system}; }).mkPoetryApplication);

      tagstudioApp = eachSystem (system:
        mkPoetryApplication.${system} rec {
          projectDir = self;

          # editablePackageSources = {
          #   tagstudio = ./tagstudio;
          # };

          exeName = "tagstudio";

          python = pkgs.${system}.python312;
          dontWrapQtApps = false;

          # preferWheels to resolve typing stubs error for opencv-python:
          #   'Failed to resolve alias "GProtoArg" exposed as "GProtoArg"'
          # https://github.com/opencv/opencv-python/issues/1010
          preferWheels = true;

          overrides = p2n-overrides.${system}.extend
            # https://github.com/nix-community/poetry2nix/blob/7619e43/docs/edgecases.md#modulenotfounderror-no-module-named-packagename
            (final: prev: {
              pyside6-essentials = prev.pyside6-essentials.overridePythonAttrs (old: {
                # prevent error: 'Error: wrapQtAppsHook is not used, and dontWrapQtApps is not set.'
                dontWrapQtApps = true;

                # satisfy some missing libraries for auto-patchelf patching PySide6-Essentials
                buildInputs = (old.buildInputs ++ (with pkgs.${system}; [
                  qt6.qtquick3d
                  qt6.qtvirtualkeyboard
                  qt6.qtwebengine
                ]))
                ++ [ ];
              });
            });

          pythonRelaxDeps = [
            # "pyside6"
          ];

          dependencies = (with pkgs.${system}; [
            # TODO only pyproject.toml PySide6 package fails to import PySide6.QtWidgets while execution
            # PySide6 Nix Package should match the same version, resolving issue would allow to use arbitrary versions
            python312.pkgs.pyside6
            #python312.pkgs.shiboken6

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
            # QT 6.7.0
            # zstd
          ])
          ++ (with pkgs.${system}; [
            # `qt6.full` prevents error with different QT version on KDE systems:
            #   'Cannot mix incompatible Qt library (6.7.2) with this library (6.7.1)'
            qt6.full
          ]);

          buildInputs = with pkgs.${system}; [
            qt6.qtbase
          ] ++ dependencies;

          nativeBuildInputs = (with pkgs.${system}; [
            copyDesktopItems
            makeWrapper
          ])
          ++ (with pkgs.${system}; [
            qt6.wrapQtAppsHook
          ])
          ++ dependencies;

          propogatedBuildInputs = with pkgs.${system}; [ ] ++ dependencies;

          libraryPath = pkgs.${system}.lib.makeLibraryPath (with pkgs.${system}; [
            "$out"
          ] ++ dependencies);

          binaryPath = pkgs.${system}.lib.makeBinPath (with pkgs.${system}; [
            "$out"
          ] ++ dependencies);

          #LD_LIBRARY_PATH = libraryPath;
          #PATH = binaryPath;

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
      # $> nix run
      # apps.default = {
      #   type = "app";
      #   # name in [tool.poetry.scripts] section of pyproject.toml
      #   program = "${tagstudioApp}/bin/${tagstudioApp.exeName}";
      # };

      # $> nix run
      packages = eachSystem (system: {
        tagstudio = tagstudioApp.${system};
        default = tagstudioApp.${system};
      });

      # Development Shell including `poetry` and `qtcreator`.
      # $> nix develop
      #
      # Use this shell for developing the application and
      # making changes to `pyproject.toml` and `poetry.lock` files.
      #
      # $> poetry install                   => generate an inital lock file
      # $> poetry lock                      => update lock file after changing dependencies
      # $> python ./tagstudio/tag_studio.py => launch application
      # $> poetry run tagstudio             => execute the application with poetry
      devShells = eachSystem (system: {
        default = pkgs.${system}.mkShell rec {
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
      });
    };
}
