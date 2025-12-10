{
  python3,
  lib,
  ...
}:
python3.pkgs.buildPythonApplication {
  pname = "nixcraft-cli";
  version = "0.1.0";

  src = ./.;

  format = "other";

  installPhase = ''
    mkdir -p $out/bin
    cp nixcraft_cli.py $out/bin/nixcraft
    chmod +x $out/bin/nixcraft
  '';

  meta = with lib; {
    description = "Command-line launcher for Nixcraft instances with logging";
    homepage = "https://github.com/Flammable-Bunny/nixcraft";
    license = licenses.mit;
    mainProgram = "nixcraft";
  };
}
