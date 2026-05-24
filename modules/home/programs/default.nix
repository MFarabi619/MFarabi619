{
  imports =
    with builtins;
    let
      exclude = [
        "default.nix"
        "surfingkeys"
      ];
    in
    map (fn: ./${fn}) (filter (fn: !(elem fn exclude)) (attrNames (readDir ./.)));
}
