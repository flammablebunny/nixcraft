{lib, ...}: {
  name,
  config,
  ...
}: {
  options = {
    username = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = name;
    };

    offline = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    uuid = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
    };

    accessTokenPath = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = ''
        Path to a file containing the Minecraft access token.
        Use nixcraft-auth to generate this file.
      '';
    };

    uuidPath = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = ''
        Path to a file containing the Minecraft UUID.
        Use nixcraft-auth to generate this file.
        If accessTokenPath is set and uuidPath is not, defaults to the uuid file
        in the same directory as the access token.
      '';
    };

    usernamePath = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = ''
        Path to a file containing the Minecraft username.
        Use nixcraft-auth to generate this file.
        If accessTokenPath is set and usernamePath is not, defaults to the username file
        in the same directory as the access token.
      '';
    };

    xuidPath = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = ''
        Path to a file containing the Xbox User ID (XUID).
        Use nixcraft-auth to generate this file.
        If accessTokenPath is set and xuidPath is not, defaults to the xuid file
        in the same directory as the access token.
      '';
    };

    userType = lib.mkOption {
      type = lib.types.enum ["msa" "mojang" "legacy"];
      default = "msa";
      description = ''
        The account type. "msa" for Microsoft accounts (default),
        "mojang" for legacy Mojang accounts, "legacy" for very old accounts.
      '';
    };

    skin = lib.mkOption {
      type = lib.types.submodule {
        options = {
          file = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Path to a skin PNG file. Can be an absolute path or just a filename
              if the skin is in ~/.local/share/nixcraft/skins/
            '';
          };

          variant = lib.mkOption {
            type = lib.types.enum ["classic" "slim"];
            default = "classic";
            description = ''
              Skin model variant. "classic" for Steve-style arms, "slim" for Alex-style arms.
            '';
          };
        };
      };
      default = {};
      description = "Skin configuration for the account";
    };

    cape = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a cape PNG file. Can be an absolute path or just a filename
        if the cape is in ~/.local/share/nixcraft/skins/capes/
      '';
    };
  };

  config = lib.mkMerge [
    {
      _module.check =
        lib.asserts.assertMsg (!(config.accessTokenPath != null && config.offline))
        "Offline accounts cannot have access token paths provided";
    }
  ];
}
