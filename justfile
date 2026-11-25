default: setup

# 공개 의존성을 검증하고 테스트한 뒤 실행 파일을 빌드한다.
setup:
    @bash dev/environment-run.sh bootstrap
    @bash dev/environment-run.sh check
    @bash dev/environment-run.sh build
