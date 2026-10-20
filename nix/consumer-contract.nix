{
  enabled,
  normalized,
  outputDirectory,
}: {
  contractVersion = 1;
  inherit enabled outputDirectory;
  enabledProviders =
    if normalized == null
    then []
    else normalized.providers;
  publicCommands = ["validate" "doctor" "plan" "export" "verify"];
}
