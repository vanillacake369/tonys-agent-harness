{lib}: rec {
  # provider adapter들이 공통으로 쓰는 attrs 정규화 helper다.
  # null 값은 재귀적으로 제거하고, 비어 있는 attrs는 provider 출력에서 생략한다.
  removeNulls = value:
    if builtins.isAttrs value
    then lib.filterAttrsRecursive (_: v: v != null) (lib.mapAttrs (_: removeNulls) value)
    else if builtins.isList value
    then map removeNulls value
    else value;

  clean = value: lib.filterAttrs (_: v: v != {}) (removeNulls value);

  # skill frontmatter는 provider가 YAML로 읽기 때문에 multiline 값을 한 줄 quoted scalar로 고정한다.
  # JSON string은 YAML double-quoted scalar와 호환되어 colon, 한글, 줄바꿈을 안전하게 다룬다.
  yamlString = value:
    builtins.toJSON (
      lib.concatStringsSep " " (
        lib.filter (line: line != "") (lib.splitString "\n" value)
      )
    );
}
