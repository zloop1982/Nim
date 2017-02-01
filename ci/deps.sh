# Some debug info
echo "Running on $CI_RUNNER_ID ($CI_RUNNER_DESCRIPTION) with tags $CI_RUNNER_TAGS."

# Packages
apt-get update -qq
apt-get install -y -qq build-essential git libcurl4-openssl-dev libsdl1.2-dev libgc-dev nodejs fasm

gcc -v

fasm -v
export PATH=$(pwd)/bin:$PATH

# Nimble deps
nim e install_nimble.nims
nim e tests/test_nimscript.nims
nimble update
nimble install zip opengl sdl1 jester@#head niminst
