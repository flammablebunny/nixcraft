{
  python3,
  lib,
  ...
}:
python3.pkgs.buildPythonApplication {
  pname = "nixcraft-skin";
  version = "0.1.0";

  src = ./.;

  format = "other";

  propagatedBuildInputs = with python3.pkgs; [
    requests
    click
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp nixcraft_skin.py $out/bin/nixcraft-skin
    chmod +x $out/bin/nixcraft-skin
  '';

  meta = with lib; {
    description = "Skin and cape manager for Nixcraft";
    homepage = "https://github.com/Flammable-Bunny/nixcraft";
    license = licenses.mit;
    mainProgram = "nixcraft-skin";
  };
}
