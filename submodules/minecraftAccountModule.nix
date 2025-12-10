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
