{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  buildInputs = [
    pkgs.lua51Packages.tl # Teal compiler
    pkgs.lua51Packages.cyan # Build manager
  ];

  shellHook = ''
    echo "Teal (tl) environment loaded."
    echo "To compile: tl gen init.tl"
    echo "To check: tl check init.tl"
  '';
}
