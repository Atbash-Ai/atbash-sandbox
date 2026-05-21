{ pkgs }: {
  deps = [
    pkgs.nodejs_20
    pkgs.bash
    pkgs.jq
    pkgs.curl
    pkgs.coreutils
  ];

  env = {
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    PATH = "$HOME/.npm-global/bin:$PATH";
  };
}
