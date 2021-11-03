{
  description = "A snake game.";
  outputs = { self, nixpkgs }: {
    defaultPackage.x86_64-linux =
      import ./. { pkgs = nixpkgs.legacyPackages.x86_64-linux; };
  };
}
