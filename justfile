default:
    @just --list --unsorted --list-submodules

# 공개 의존성을 검증하고 테스트한 뒤 실행 파일을 빌드한다.
setup:
    @bash dev/environment-run.sh bootstrap
    @bash dev/environment-run.sh check
    @bash dev/environment-run.sh build

# Run the full repository checks and build without changing dependency pins.
verify:
    @bash dev/environment-run.sh check
    @bash dev/environment-run.sh build

# 현재 체크아웃을 빌드해 설치한다. 버전을 주면 GitHub Release에서 설치한다.
[positional-arguments]
install *args:
    @if [ "$#" -eq 0 ] || [ "$1" = "--bin-dir" ]; then sh dev/install-local.sh "$@"; else sh install.sh "$@"; fi

# 최신 또는 지정한 GitHub Release에서 Harness를 설치한다.
[positional-arguments]
install-release *args:
    @sh install.sh "$@"
