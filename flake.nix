{
  description = "TagStudio";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Pinned to Qt version 6.7.1
    nixpkgs-qt6.url = "github:NixOS/nixpkgs/e6cea36f83499eb4e9cd184c8a8e823296b50ad5";

    systems.url = "github:nix-systems/default-linux";

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

    poetry2nix.url = "github:nix-community/poetry2nix";
  };

  outputs = { self, nixpkgs, flake-utils, ... } @inputs:
    # TODO https://github.com/NixOS/templates/blob/master/python/flake.nix
    inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        inherit (nixpkgs) lib;

        qt6Pkgs = import inputs.nixpkgs-qt6 { inherit system; };

        # see https://github.com/nix-community/poetry2nix/tree/master#api for more functions and examples.
        pkgs = nixpkgs.legacyPackages.${system}.extend inputs.poetry2nix.overlays.default;

        # override some missing dependencies for python packages
        # https://github.com/nix-community/poetry2nix/blob/8ffbc64abe7f432882cb5d96941c39103622ae5e/docs/edgecases.md#modulenotfounderror-no-module-named-packagename
        pypkgs-build-requirements = {
          #python-xlib = [ "setuptools" "setuptools-scm" ];
        };
        p2n-overrides = pkgs.poetry2nix.defaultPoetryOverrides.extend (self: super:
          builtins.mapAttrs
            (package: build-requirements:
              (builtins.getAttr package super).overridePythonAttrs (old: {
                buildInputs = (old.buildInputs or [ ]) ++ (builtins.map (pkg: if builtins.isString pkg then builtins.getAttr pkg super else pkg) build-requirements);
              })
            )
            pypkgs-build-requirements
        );

        inherit (inputs.poetry2nix.lib.mkPoetry2Nix { inherit pkgs; }) mkPoetryApplication;

        tagstudioApp = mkPoetryApplication rec {
          projectDir = self;

          # editablePackageSources = {
          #   tagstudio = ./tagstudio;
          # };

          exeName = "tagstudio";

          python = pkgs.python312Full;
          dontWrapQtApps = false;

          # preferWheels to resolve typing stubs error for opencv-python:
          #   'Failed to resolve alias "GProtoArg" exposed as "GProtoArg"'
          # https://github.com/opencv/opencv-python/issues/1010
          preferWheels = true;

          overrides = p2n-overrides.extend
            # https://github.com/nix-community/poetry2nix/blob/7619e43/docs/edgecases.md#modulenotfounderror-no-module-named-packagename
            (final: prev: {
              pyside6-essentials = prev.pyside6-essentials.overridePythonAttrs (old: {
                # prevent error: 'Error: wrapQtAppsHook is not used, and dontWrapQtApps is not set.'
                dontWrapQtApps = true;

                # satisfy some missing libraries for auto-patchelf patching PySide6-Essentials
                buildInputs = (old.buildInputs ++ (with pkgs; [
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

          dependencies = (with pkgs; [
            # TODO only pyproject.toml PySide6 package fails to import PySide6.QtCore while execution
            # PySide6 Nix Package should match the same version, resolving issue would allow to use arbitrary versions
            python312Full.pkgs.pyside6

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
          ++ (with pkgs; [
            # `qt6.full` prevents error with different QT version on KDE systems:
            #   'Cannot mix incompatible Qt library (6.7.2) with this library (6.7.1)'
            qt6.full
          ]);

          buildInputs = with pkgs; [
            qt6.qtbase
          ] ++ dependencies;

          nativeBuildInputs = (with pkgs; [
            copyDesktopItems
            makeWrapper
          ])
          ++ (with pkgs; [
            qt6.wrapQtAppsHook
          ])
          ++ dependencies;

          propogatedBuildInputs = with pkgs; [ ] ++ dependencies;

          libraryPath = lib.makeLibraryPath (with pkgs; [
            "$out"
          ] ++ dependencies);

          binaryPath = lib.makeBinPath (with pkgs; [
            "$out"
          ] ++ dependencies);

          desktopItems = [
            (pkgs.makeDesktopItem {
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
        };
      in
      {
        # $> nix run .
        # apps.default = {
        #   type = "app";
        #   # name in [tool.poetry.scripts] section of pyproject.toml
        #   program = "${tagstudioApp}/bin/${tagstudioApp.exeName}";
        # };

        # $> nix build .
        packages = {
          tagstudio = tagstudioApp;
          default = tagstudioApp;
        };

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
        devShells.default = pkgs.mkShell rec {
          inputsFrom = [ self.packages.${system}.tagstudio ];

          packages = with pkgs; [
            poetry
            cmake
            mypy
            ruff
          ] ++ (with pkgs; [
            qtcreator
          ])
          ++ tagstudioApp.dependencies;

          LD_LIBRARY_PATH = lib.makeLibraryPath packages;
        };
      });
}
