{lib, ...}: let
  inherit (builtins) readDir fromJSON readFile;
  inherit (lib) mapAttrs' nameValuePair removeSuffix filterAttrs;

  # Read all JSON files in this directory
  files = filterAttrs (n: v: v == "regular" && lib.hasSuffix ".json" n) (readDir ./.);

  # Parse each JSON file and create a version -> data mapping
  versions = mapAttrs' (name: _: let
    version = removeSuffix ".json" name;
    data = fromJSON (readFile (./. + "/${name}"));
  in nameValuePair version data) files;
in {
  inherit versions;
}
