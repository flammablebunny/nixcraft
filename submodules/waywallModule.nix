# Waywall is a wayland compositor that runs minecraft. Used for mcsr (minecraft speedrunning)
{
  lib,
  fileModule,
  ...
}: {
  name,
  config,
  ...
}: {
  options = {
    enable = lib.mkEnableOption "waywall";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "The waywall package to use. If null and binaryPath is set, binaryPath is used instead.";
    };

    binaryPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Direct path to the waywall binary as a string.
        Takes precedence over package if both are set.
        Example: "/home/user/waywall/result/bin/waywall"
      '';
    };

    command = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.str (lib.types.listOf lib.types.str));
      default = null;
      description = ''
        Full custom waywall wrapper command. Takes precedence over binaryPath and package.
        - If a string: used as-is (for shell commands or simple paths)
          - If it looks like a path (starts with / or ./): adds "wrap --" automatically
          - Otherwise: used verbatim as a shell command (game script path appended as $1)
        - If a list: args are escaped and joined (game script appended)
        Example: ["env" "DRI_PRIME=renderD128" "/path/to/waywall" "wrap" "--"]
      '';
      example = lib.literalExpression ''
        # List form (recommended) - args are properly escaped
        ["env" "DRI_PRIME=renderD128" "/path/to/waywall" "wrap" "--"]

        # Simple path string - auto-adds "wrap --"
        "/path/to/waywall"

        # Full shell command string - used verbatim, game script is $1
        "env DRI_PRIME=renderD128 /path/to/waywall wrap --"
      '';
    };

    rawCommand = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.str (lib.types.listOf lib.types.str));
      default = null;
      description = ''
        Raw shell command with access to special variables. Takes precedence over all other command options.
        Available variables:
        - $GAME_SCRIPT: path to the game launch script
        - $INST_JAVA: path to the Java binary for this instance
        The command is evaluated in bash with these variables exported.

        Can be specified as:
        - A string: used verbatim (requires careful escaping)
        - A list: arguments are joined with spaces, no additional escaping
          Use list format to avoid quote escaping issues when command contains = and quotes

        Example (string): "env VAR=val /path/to/waywall wrap -- $GAME_SCRIPT"
        Example (list): ["env" "VAR=val" "/path/to/waywall" "wrap" "--" "$GAME_SCRIPT"]
      '';
      example = lib.literalExpression ''
        # List format (recommended for complex commands with = and quotes):
        [
          "env"
          "__GLX_VENDOR_LIBRARY_NAME=amd"
          "GBM_DEVICE=/dev/dri/renderD129"
          "/home/user/waywall/bin/waywall"
          "wrap"
          "--"
          "env"
          "__GLX_VENDOR_LIBRARY_NAME=intel"
          "DRI_PRIME=1"
          "$GAME_SCRIPT"
        ]

        # String format:
        "env __GLX_VENDOR_LIBRARY_NAME=amd /home/user/waywall/bin/waywall wrap -- $GAME_SCRIPT"
      '';
    };

    glfwPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Custom GLFW package for waywall. If null, uses the default glfw3-waywall package.
        Set this if you have a custom-built GLFW with waywall patches.
      '';
    };

    glfwPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Direct path to a custom libglfw.so file as a string.
        Takes precedence over glfwPackage if both are set.
        Example: "/home/user/glfw/build/src/libglfw.so"
      '';
    };

    profile = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      example = "foo";
      default = null;
    };

    configText = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      description = ''
        Lua script passed as init.lua
      '';
      default = null;
    };

    configDir = lib.mkOption {
      type = lib.types.nullOr (lib.types.pathWith {absolute = true;});
      description = ''
        Path to a dir containing waywall scripts such as init.lua
        If not set then $XDG_CONFIG_HOME/waywall is used as usual
      '';
      example = ''
        pkgs.linkFarm {
          "init.lua" = builtins.toFile "init.lua" "<content>";
        };
      '';
      default = null;
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (config.configText != null) {
      profile = null;
    })

    # TODO: find correct way to do validations
    {
      _module.check = lib.all (a: a) [
        (
          lib.assertMsg
          ((lib.count (v: v != null) [
              config.configDir
              config.configText
            ])
            <= 1) "either .configText or .configDir needs to be set not both"
        )
      ];
    }
  ];
}
