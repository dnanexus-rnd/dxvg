#!/bin/bash

main() {
    set -ex -o pipefail

    # install dependencies
    sudo rm -f /etc/apt/apt.conf.d/99dnanexus
    sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
    sudo add-apt-repository -y ppa:kalakris/cmake
    sudo apt-get -qq update
    sudo apt-get install -y -qq gcc-4.9 g++-4.9 cmake
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.9 100 \
                             --slave /usr/bin/g++ g++ /usr/bin/g++-4.9
    JQFN=$(which jq)
    curl -L https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 > "$JQFN"
    chmod +x "$JQFN"

    # clone vg git repository
    git clone -n "$git_url" vg
    cd vg
    git checkout "$git_commit"
    git submodule update --init --recursive

    # detect revision
    GIT_REVISION=$(git describe --long --tags --dirty --always)

    # build and test
    make -j$(nproc)
    make test

    # upload the exe
    vg_exe=$(gzip -c vg | dx upload --destination "vg-exe-${GIT_REVISION}.gz" --type vg_exe \
                                    --property "git_revision=${GIT_REVISION}" --brief -)
    dx-jobutil-add-output vg_exe "$vg_exe" --class=file
}
