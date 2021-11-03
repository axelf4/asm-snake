{ pkgs ? import <nixpkgs> {} }: with pkgs; stdenv.mkDerivation {
  pname = "snake";
  version = "1.0.0";

  src = ./.;

  installPhase = ''
    mkdir -p $out/bin
    cp snake $out/bin
  '';

  meta = with lib; {
    description = "A remake of the game Snake";
    homepage = "https://github.com/axelf4/asm-snake";
    platforms = [ "x86_64-linux" ];
  };
}
