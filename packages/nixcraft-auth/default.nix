{
  python3,
  lib,
  ...
}:
python3.pkgs.buildPythonApplication {
  pname = "nixcraft-auth";
  version = "0.1.0";

  src = ./.;

  format = "other";

  propagatedBuildInputs = with python3.pkgs; [
    requests
    click
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp nixcraft_auth.py $out/bin/nixcraft-auth
    chmod +x $out/bin/nixcraft-auth
  '';

  meta = with lib; {
    description = "Microsoft authentication helper for Nixcraft";
    homepage = "https://github.com/Flammable-Bunny/nixcraft";
    license = licenses.mit;
    mainProgram = "nixcraft-auth";
  };
}
