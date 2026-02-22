{
  lib,
  pkgs,
  forgeLoaderModule,
  fabricLoaderModule,
  mrpackModule,
  javaSettingsModule,
  genericInstanceModule,
  waywallModule,
  minecraftAccountModule,
  sources,
  fetchSha1,
  mkAssetsDir,
  mkLibDir,
  mkNativeLibDir,
  inputs,
  system,
  ...
}: let
  inherit (lib) escapeShellArgs escapeShellArg concatStringsSep;
  inherit (lib.nixcraft.filesystem) listJarFilesRecursive;

  # Helper to check if a library name contains LWJGL
  isLwjglLibrary = lib: builtins.match ".*org\\.lwjgl.*" lib.name != null;

  # Filter out LWJGL libraries from a list
  filterOutLwjgl = libraries: builtins.filter (lib: !isLwjglLibrary lib) libraries;
in
  {
    name,
    config,
    shared ? {},
    ...
  }: {
    imports = [genericInstanceModule];

    options = {
      enable = lib.mkEnableOption "client instance";

      waywall = lib.mkOption {
        type = lib.types.submodule waywallModule;
      };

      # MangoHud overlay support
      mangohud = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "MangoHud overlay";
            configFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Path to MangoHud config file";
            };
          };
        };
        default = {};
      };

      # Generic wrapper command (runs before the game)
      wrapper = lib.mkOption {
        type = lib.types.nullOr (lib.types.either lib.types.str (lib.types.listOf lib.types.str));
        default = null;
        description = ''
          Custom wrapper command for the game.
          - If a string (path): uses "<path> wrap --" as the wrapper
          - If a list: uses the list as the full command (game script appended)
          Example: "/path/to/wrapper" or ["gamemoderun"] or ["env" "VAR=value" "command"]
        '';
        example = lib.literalExpression ''
          "/usr/bin/gamemoderun"
          # or
          ["gamemoderun"]
          # or
          ["env" "MANGOHUD=1" "gamemoderun"]
        '';
      };

      enableNvidiaOffload = lib.mkEnableOption "nvidia offload";

      enableDriPrime = lib.mkEnableOption "dri prime (mesa)";

      useDiscreteGPU =
        (lib.mkEnableOption "discrete GPU")
        // {
          default = true;
        };

      # Hide these two option for now
      enableFastAssetDownload =
        (lib.mkEnableOption "fast asset downloading using aria2c (hash needs to be provided)")
        // {
          internal = true;
        };

      assetHash = lib.mkOption {
        type = lib.types.nonEmptyStr;
        internal = true;
      };

      desktopEntry = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "desktop entry";
            name = lib.mkOption {
              type = lib.types.nonEmptyStr;
              default = "Nixcraft Instance ${name}";
            };
            icon = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Path to the icon file for the desktop entry";
            };
            extraConfig = lib.mkOption {
              type = lib.types.attrs;
              default = {};
            };
          };
        };
        default = {
          enable = false;
        };
      };

      account = lib.mkOption {
        type = with lib.types; nullOr (submodule minecraftAccountModule);
        default = null;
      };

      lwjglVersion = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum ["3.3.3"]);
        default = null;
        description = ''
          Override the LWJGL version used by the instance.
          Set to "3.3.3" to use LWJGL 3.3.3 (required for some speedrunning setups).
          When null (default), uses the LWJGL version from the Minecraft manifest.
        '';
      };

      saves = lib.mkOption {
        type = lib.types.attrsOf (lib.types.path);
        default = {};
        description = ''
          World saves. Placed only if the directory already doesn't exist
          {
            "My World" = /path/to/world
          }
        '';
      };

      extraArguments = lib.mkOption {
        type = with lib.types; listOf nonEmptyStr;
        default = [];
      };

      finalArgumentShellString = lib.mkOption {
        type = with lib.types; nonEmptyStr;
        readOnly = true;
        default = with lib;
          let
            # Build most args with escapeShellArgs
            staticArgs = escapeShellArgs (
              concatLists [
                ["--version" config._classSettings.version]
                ["--assetIndex" config._classSettings.assetIndex]

                (
                  let
                    cond = config._classSettings.userProperties != null;
                  in
                    (optional cond "--userProperties") ++ (optional cond (builtins.toJSON config._classSettings.userProperties))
                )

                (
                  let
                    cond = config._classSettings.gameDir != null;
                  in
                    (optional cond "--gameDir") ++ (optional cond config._classSettings.gameDir)
                )

                (
                  let
                    cond = config._classSettings.username != null;
                  in
                    (optional cond "--username") ++ (optional cond config._classSettings.username)
                )

                (
                  let
                    cond = config._classSettings.uuid != null;
                  in
                    (optional cond "--uuid") ++ (optional cond config._classSettings.uuid)
                )

                (
                  let
                    cond = config._classSettings.height != null;
                  in
                    (optional cond "--height") ++ (optional cond (toString config._classSettings.height))
                )

                (
                  let
                    cond = config._classSettings.width != null;
                  in
                    (optional cond "--width") ++ (optional cond (toString config._classSettings.width))
                )

                (optional (config._classSettings.fullscreen) "--fullscreen")

                config.extraArguments
              ]
            );
            # assetsDir uses shell variable, so don't escape it
            assetsDirArg = ''--assetsDir "$NIXCRAFT_ASSETS_DIR"'';
          in
            "${staticArgs} ${assetsDirArg}";
      };

      _classSettings = lib.mkOption {
        type = with lib.types;
          submodule {
            options = {
              version = lib.mkOption {
                type = lib.types.nonEmptyStr;
              };

              # The read-only source assets directory (in nix store)
              sourceAssetsDir = lib.mkOption {
                type = lib.types.path;
                description = "Read-only assets directory from nix store";
              };

              # The writable assets directory (used at runtime)
              assetsDir = lib.mkOption {
                type = lib.types.str;
                description = "Writable assets directory path (used at runtime)";
              };

              assetIndex = lib.mkOption {
                type = lib.types.nonEmptyStr;
              };

              userProperties = lib.mkOption {
                type = lib.types.nullOr lib.types.attrs;
                default = null;
              };

              gameDir = lib.mkOption {
                type = lib.types.nullOr lib.types.nonEmptyStr;
                default = null;
              };

              username = lib.mkOption {
                type = lib.types.nullOr lib.types.nonEmptyStr;
                default = null;
              };

              uuid = lib.mkOption {
                type = lib.types.nullOr lib.types.nonEmptyStr;
                default = null;
              };

              fullscreen = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };

              height = lib.mkOption {
                type = lib.types.nullOr lib.types.ints.positive;
                default = null;
              };

              width = lib.mkOption {
                type = lib.types.nullOr lib.types.ints.positive;
                default = null;
              };
            };
          };
      };
    };

    config = lib.mkMerge [
      shared

      {
        finalLaunchShellCommandString = let
          # Determine auth file paths
          hasRuntimeAuth = config.account != null && config.account.accessTokenPath != null;
          authDir = if hasRuntimeAuth then builtins.dirOf config.account.accessTokenPath else null;

          # UUID: use uuidPath if set, otherwise derive from accessTokenPath directory
          uuidSource =
            if hasRuntimeAuth then
              if config.account.uuidPath != null
              then config.account.uuidPath
              else "${authDir}/uuid"
            else null;

          # Username: use usernamePath if set, otherwise derive from accessTokenPath directory
          usernameSource =
            if hasRuntimeAuth then
              if config.account.usernamePath != null
              then config.account.usernamePath
              else "${authDir}/username"
            else null;

          # XUID: use xuidPath if set, otherwise derive from accessTokenPath directory
          xuidSource =
            if hasRuntimeAuth then
              if config.account.xuidPath != null
              then config.account.xuidPath
              else "${authDir}/xuid"
            else null;

          # User type for Microsoft accounts
          userType = if config.account != null then config.account.userType else "msa";

          # Runtime auth arguments (read from files at launch time)
          runtimeAuthArgs =
            if hasRuntimeAuth then
              concatStringsSep " " [
                "--accessToken $(cat ${escapeShellArg config.account.accessTokenPath})"
                "--uuid $(cat ${escapeShellArg uuidSource})"
                "--username $(cat ${escapeShellArg usernameSource})"
                "--userType ${userType}"
                "--xuid $(cat ${escapeShellArg xuidSource})"
              ]
            else "--accessToken dummy";
        in concatStringsSep " " [
          ''"${config.java.package}/bin/java"''
          config.java.finalArgumentShellString
          config.finalArgumentShellString
          runtimeAuthArgs
        ];

        finalLaunchShellScript = let
          # Base script that runs the game
          baseScript = ''
            #!${pkgs.bash}/bin/bash

            set -e

            # Export instance Java path for wrapper commands
            export INST_JAVA="${config.java.package}/bin/java"

            ${lib.nixcraft.mkExportedEnvVars config.envVars}

            ${config.finalPreLaunchShellScript}

            cd "${config.absoluteDir}"

            exec ${config.finalLaunchShellCommandString} "$@"
          '';

          # Write base script to file
          baseScriptFile = pkgs.writeTextFile {
            name = "run-base";
            text = baseScript;
            executable = true;
          };

          # Apply custom wrapper if set
          # - If string (path): use "<path> wrap --"
          # - If list: use as full command
          wrapperCommand =
            if config.wrapper == null then null
            else if builtins.isString config.wrapper then
              ''"${config.wrapper}" wrap --''
            else
              escapeShellArgs config.wrapper;

          wrappedScript =
            if wrapperCommand != null then
              pkgs.writeTextFile {
                name = "run-wrapped";
                text = ''
                  #!${pkgs.bash}/bin/bash
                  set -e
                  exec ${wrapperCommand} "${baseScriptFile}" "$@"
                '';
                executable = true;
              }
            else baseScriptFile;

          # Apply waywall wrapper if enabled
          finalScript =
            if config.waywall.enable then
              let
                configDirStr = lib.optionalString (config.waywall.configDir != null) "XDG_CONFIG_HOME=${(pkgs.linkFarm "waywall-config-dir" {
                  waywall = config.waywall.configDir;
                })}";

                configTextStr = lib.optionalString (config.waywall.configText != null) "XDG_CONFIG_HOME=${(pkgs.linkFarm "waywall-config-dir" {
                  "waywall/init.lua" = pkgs.writeTextFile {
                    name = "init.lua";
                    text = config.waywall.configText;
                  };
                })}";

                profileStr = lib.optionalString (config.waywall.profile != null) "--profile ${lib.escapeShellArg config.waywall.profile}";

                # rawCommand takes highest precedence - uses GAME_SCRIPT variable
                # Full custom command takes precedence
                # - If command is a list: args are escaped and joined
                # - If command is a string starting with / or ./: treat as path, add "wrap --"
                # - If command is any other string: use verbatim as shell command
                # - Otherwise fall back to binaryPath or package
                waywallCommand =
                  if config.waywall.rawCommand != null then
                    null  # handled separately below
                  else if config.waywall.command != null then
                    if builtins.isList config.waywall.command then
                      escapeShellArgs config.waywall.command
                    else if builtins.isString config.waywall.command then
                      let
                        cmd = config.waywall.command;
                        isPath = lib.hasPrefix "/" cmd || lib.hasPrefix "./" cmd;
                      in
                        if isPath then
                          ''"${cmd}" wrap ${profileStr} --''
                        else
                          # Full shell command - used verbatim
                          "${cmd}"
                    else
                      throw "waywall.command must be a string or list"
                  else
                    let
                      waywallBin =
                        if config.waywall.binaryPath != null
                        then config.waywall.binaryPath
                        else if config.waywall.package != null
                        then "${config.waywall.package}/bin/waywall"
                        else "${pkgs.waywall}/bin/waywall";
                    in ''"${waywallBin}" wrap ${profileStr} --'';
              in
                if config.waywall.rawCommand != null then
                  let
                    # Handle both string and list formats for rawCommand
                    rawCommandStr =
                      if builtins.isList config.waywall.rawCommand then
                        # List format: join with spaces (variables like $GAME_SCRIPT will expand at runtime)
                        concatStringsSep " " config.waywall.rawCommand
                      else
                        # String format: use verbatim
                        config.waywall.rawCommand;
                  in
                  # rawCommand mode: export GAME_SCRIPT and INST_JAVA, then exec the raw command
                  ''
                    #!${pkgs.bash}/bin/bash

                    set -e

                    export GAME_SCRIPT="${wrappedScript}"
                    export INST_JAVA="${config.java.package}/bin/java"

                    ${configDirStr} ${configTextStr} exec ${rawCommandStr}
                  ''
                else
                  ''
                    #!${pkgs.bash}/bin/bash

                    set -e

                    ${configDirStr} ${configTextStr} exec ${waywallCommand} "${wrappedScript}" "$@"
                  ''
            else
              builtins.readFile wrappedScript;
        in finalScript;

        finalActivationShellScript = ''
          ${config.activationShellScript}
        '';

        finalPreLaunchShellScript = ''
          ${config.preLaunchShellScript}
        '';

        # set waywall stuff - defaults removed, now optional
        waywall = {};
      }

      # Set up writable assets directory (allows Minecraft to cache skins)
      {
        preLaunchShellScript = let
          sourceAssetsDir = config._classSettings.sourceAssetsDir;
        in ''
          # Create writable assets directory structure
          NIXCRAFT_ASSETS_DIR="$HOME/.local/share/nixcraft/assets"
          export NIXCRAFT_ASSETS_DIR

          mkdir -p "$NIXCRAFT_ASSETS_DIR"

          # Symlink indexes directory from nix store (update if stale)
          if [ -L "$NIXCRAFT_ASSETS_DIR/indexes" ] && [ ! -e "$NIXCRAFT_ASSETS_DIR/indexes" ]; then
            rm "$NIXCRAFT_ASSETS_DIR/indexes"
          fi
          if [ ! -e "$NIXCRAFT_ASSETS_DIR/indexes" ]; then
            ln -s "${sourceAssetsDir}/indexes" "$NIXCRAFT_ASSETS_DIR/indexes"
          fi

          # Symlink objects directory from nix store (update if stale)
          if [ -L "$NIXCRAFT_ASSETS_DIR/objects" ] && [ ! -e "$NIXCRAFT_ASSETS_DIR/objects" ]; then
            rm "$NIXCRAFT_ASSETS_DIR/objects"
          fi
          if [ ! -e "$NIXCRAFT_ASSETS_DIR/objects" ]; then
            ln -s "${sourceAssetsDir}/objects" "$NIXCRAFT_ASSETS_DIR/objects"
          fi

          # Create writable skins directory for caching
          # Skins are cached after first download - subsequent loads are instant
          mkdir -p "$NIXCRAFT_ASSETS_DIR/skins"
        '';
      }

      # Place saves
      {
        preLaunchShellScript = let
          absSavesPath = "${config.absoluteDir}/saves";

          placeSaves =
            lib.concatMapAttrsStringSep "\n" (name: path: let
              absPlacePath = "${config.absoluteDir}/saves/${name}";
            in ''
              if [ ! -d ${escapeShellArg absPlacePath} ]; then
                rm -rf ${escapeShellArg absPlacePath}
                cp -R ${escapeShellArg path} ${escapeShellArg absPlacePath}
                chmod -R u+w ${escapeShellArg absPlacePath}
              fi
            '')
            config.saves;
        in ''
          if [ ! -d ${escapeShellArg absSavesPath} ]; then
            rm -f ${escapeShellArg absSavesPath}
            mkdir -p ${escapeShellArg absSavesPath}
            chmod -R u+w ${escapeShellArg absSavesPath} || true
          fi

          ${placeSaves}
        '';
      }

      # Apply skin before launch if configured
      (lib.mkIf (config.account != null && config.account.skin.file != null && config.account.accessTokenPath != null) {
        preLaunchShellScript = let
          skinPath = config.account.skin.file;
          variant = config.account.skin.variant;
          tokenPath = config.account.accessTokenPath;
        in ''
          # Apply skin to Minecraft account
          echo "Applying skin (${variant})..."
          if ${pkgs.curl}/bin/curl -s -X POST \
            -H "Authorization: Bearer $(cat ${escapeShellArg tokenPath})" \
            -F "variant=${variant}" \
            -F "file=@${skinPath}" \
            "https://api.minecraftservices.com/minecraft/profile/skins" \
            -o /dev/null -w "%{http_code}" | grep -q "^20"; then
            echo "Skin applied successfully"
          else
            echo "Warning: Failed to apply skin (continuing anyway)"
          fi
        '';
      })

      {
        _classSettings = {
          version = lib.mkOptionDefault config.meta.versionData.id;
          assetIndex = config.meta.versionData.assets;

          # Source assets from nix store (read-only)
          sourceAssetsDir =
            if config.enableFastAssetDownload
            then
              (mkAssetsDir {
                versionData = config.meta.versionData;
                hash = config.assetHash;
                useAria2c = config.enableFastAssetDownload;
              })
            else mkAssetsDir {versionData = config.meta.versionData;};

          # Writable assets directory (allows skin caching)
          assetsDir = "\${NIXCRAFT_ASSETS_DIR}";

          gameDir = lib.mkDefault config.absoluteDir;
        };

        libraries = config.meta.versionData.libraries;

        mainJar = lib.mkDefault (fetchSha1 config.meta.versionData.downloads.client);

        # TODO: in javaSettingsModule try to implement this as an actual option
        java.extraArguments = ["-Djava.library.path=${mkNativeLibDir {versionData = config.meta.versionData;}}"];

        java.mainClass = lib.mkDefault config.meta.versionData.mainClass;

        # Default libs copied over from
        # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/pr/prismlauncher/package.nix#L78
        runtimeLibs = with pkgs;
        with xorg; [
          (lib.getLib stdenv.cc.cc)
          ## native versions
          glfw3-minecraft
          openal

          ## openal
          alsa-lib
          libjack2
          libpulseaudio
          pipewire

          ## glfw
          libGL
          libX11
          libXcursor
          libXext
          libXrandr
          libXxf86vm

          udev # oshi

          vulkan-loader # VulkanMod's lwjgl

          flite # TTS

          libxtst
          libxkbcommon
          libxt
        ];

        runtimePrograms = with pkgs;
        with xorg; [
          xrandr # This is needed for 1.12.x versions to not crash
        ];

        # inform generic settings module the instance type
        _instanceType = "client";
      }

      # TODO: implement fast asset download
      (lib.mkIf config.enableFastAssetDownload {
        assetHash = lib.mkOptionDefault lib.fakeHash;
      })

      (lib.mkIf config.enableNvidiaOffload {
        envVars = {
          __NV_PRIME_RENDER_OFFLOAD = "1";
          __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
          __VK_LAYER_NV_optimus = "NVIDIA_only";
        };
      })

      (lib.mkIf config.enableDriPrime {
        envVars = {
          DRI_PRIME = "1";
        };
      })

      # MangoHud overlay support
      (lib.mkIf config.mangohud.enable {
        envVars = {
          MANGOHUD = "1";
        } // lib.optionalAttrs (config.mangohud.configFile != null) {
          MANGOHUD_CONFIGFILE = toString config.mangohud.configFile;
        };
      })

      (lib.mkIf config.useDiscreteGPU {
        enableDriPrime = true;
        enableNvidiaOffload = true;
      })

      (lib.mkIf config.fixBugs (lib.mkMerge [
        (lib.mkIf config.enableNvidiaOffload {
          # Prevents minecraft from segfaulting on exit
          envVars.__GL_THREADED_OPTIMIZATIONS = "0";
        })
      ]))

      (lib.mkIf config.forgeLoader.enable {
        java.mainClass = "net.minecraftforge.bootstrap.ForgeBootstrap";
        _classSettings.version = config.forgeLoader.parsedForgeLoader.versionId;
        extraArguments = ["--launchTarget" "forge_client"];
        mainJar = let installDir = config.forgeLoader.parsedForgeLoader.clientInstallDirWithClientJar (fetchSha1 config.meta.versionData.downloads.client); in "${installDir}/libraries/net/minecraftforge/forge/${config.forgeLoader.minecraftVersion}-${config.forgeLoader.version}/forge-${config.forgeLoader.minecraftVersion}-${config.forgeLoader.version}-client.jar";
        libraries = config.forgeLoader.parsedForgeLoader.versionLibraries;
      })

      (lib.mkIf config.fabricLoader.enable {
        java.mainClass = config.fabricLoader.meta.clientMainClass;
      })

      (lib.mkIf config.quiltLoader.enable {
        java.mainClass = config.quiltLoader.meta.lock.mainClass.client;
      })

      (lib.mkIf config.waywall.enable {
        # Pull in waywall's runtime dependencies into LD_LIBRARY_PATH
        runtimeLibs = [ pkgs.libircclient ];

        # waywall uses custom libglfw.so
        java.extraArguments = let
          glfwLibPath =
            if config.waywall.glfwPath != null
            then config.waywall.glfwPath
            else if config.waywall.glfwPackage != null
            then "${config.waywall.glfwPackage}/lib/libglfw.so"
            else "${inputs.self.packages.${system}.glfw3-waywall}/lib/libglfw.so";
        in [
          "-Dorg.lwjgl.glfw.libname=${glfwLibPath}"
        ];
      })

      # If version >= 1.6 && version <= 1.12
      (with lib.nixcraft.minecraftVersion;
        lib.mkIf ((grEq config.version "1.6") && (lsEq config.version "1.12"))
        {
          # Fixes versions crashing without userProperties
          _classSettings.userProperties = lib.mkDefault {};
        })

      # Only set static uuid/username when NOT using runtime auth (accessTokenPath)
      # When accessTokenPath is set, uuid/username are read from files at runtime
      (lib.mkIf (config.account != null && config.account.accessTokenPath == null) {
        _classSettings.uuid = lib.mkIf (config.account.uuid != null) config.account.uuid;
        _classSettings.username = lib.mkIf (config.account.username != null) config.account.username;
      })

      # LWJGL version override
      (lib.mkIf (config.lwjglVersion != null) (let
        lwjglData = sources.lwjgl3.versions.${config.lwjglVersion};
        lwjglLibraries = lwjglData.libraries;
      in {
        # Replace vanilla LWJGL libraries with the override version
        libraries = lib.mkForce (
          (filterOutLwjgl config.meta.versionData.libraries) ++ lwjglLibraries
        );
      }))
    ];
  }
