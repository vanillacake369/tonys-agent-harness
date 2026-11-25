let
  catalog = builtins.fromJSON (builtins.readFile ./provider-catalog.json);
  servers = catalog.mcp_servers;
  codex =
    builtins.concatStringsSep "\n" (
      ["[tui]"]
      ++ builtins.concatLists (
        map (name: [
          "[mcp_servers.${name}]"
          "url = \"${servers.${name}.url}\""
        ]) (builtins.attrNames servers)
      )
    )
    + "\n";
  render = provider:
    if provider.adapter == "codex-toml"
    then codex
    else if provider.adapter == "kiro-json"
    then {
      mcpServers = builtins.mapAttrs (_: server: server // {autoApprove = [];}) servers;
    }
    else if provider.adapter == "claude-http"
    then {
      mcpServers = builtins.mapAttrs (_: server: server // {type = "http";}) servers;
    }
    else throw "Unknown provider adapter: ${provider.adapter}";
in {
  fragments = builtins.listToAttrs (
    map (provider: {
      name = provider.name;
      value = {
        fileName = provider.fragment_file;
        value = render provider;
      };
    })
    catalog.providers
  );
  plugins = catalog.plugins;
}
