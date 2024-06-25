#!/bin/bash
# Copyright (C) 2015-2024 Florent Revest
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

declare -a devices=("anthias" "bass" "beluga" "catfish" "dory" "firefish" "harmony" "hoki" "koi" "inharmony" "lenok" "minnow" "mooneye" "narwhal" "nemo" "pike" "qemux86" "ray" "smelt" "sparrow" "sparrow-mainline" "sprat" "sturgeon" "sawfish" "skipjack" "swift" "tetra" "triggerfish" "wren")

declare -a layers=(
    "src/oe-core                   https://github.com/openembedded/openembedded-core.git kirkstone"
    "src/oe-core/bitbake           https://github.com/openembedded/bitbake.git           master"
    "src/meta-openembedded         https://github.com/openembedded/meta-openembedded.git master"
    "src/meta-qt5                  https://github.com/meta-qt5/meta-qt5.git              master"
    "src/meta-smartphone           https://github.com/shr-distribution/meta-smartphone.git master"
    "src/meta-asteroid             https://github.com/AsteroidOS/meta-asteroid.git       master"
    "src/meta-asteroid-community   https://github.com/AsteroidOS/meta-asteroid-community.git master"
    "src/meta-smartwatch           https://github.com/AsteroidOS/meta-smartwatch.git     master"
)

declare -a layers_conf=(
    "meta-qt5"
    "oe-core/meta"
    "meta-asteroid"
    "meta-asteroid-community"
    "meta-openembedded/meta-oe"
    "meta-openembedded/meta-multimedia"
    "meta-openembedded/meta-gnome"
    "meta-openembedded/meta-networking"
    "meta-smartphone/meta-android"
    "meta-openembedded/meta-python"
    "meta-openembedded/meta-filesystems"
)

function printNoDeviceInfo {
    echo "Usage:"
    echo -e "Updating the sources:\t$ . ./prepare-build.sh update"
    echo -e "Building AsteroidOS:\t$ . ./prepare-build.sh device\n"
    echo -e "Available devices:\n"

    for device in "${devices[@]}"; do
        echo "$device"
    done

    echo -e "\nWiki - Building AsteroidOS: https://asteroidos.org/wiki/building-asteroidos/"

    return 1
}

function pull_dir {
    if [ -d "$1/.git/" ]; then
        [ "$1" != "." ] && pushd "$1" > /dev/null
        echo -e "\e[32mPulling $1\e[39m"
        if git remote get-url upstream &> /dev/null; then
            git pull upstream --rebase "$2"
        else
            git pull --rebase
        fi
        if [ $? -ne 0 ]; then
            echo -e "\e[91mError pulling $1\e[39m"
        fi
        git checkout "$2"
        [ "$1" != "." ] && popd > /dev/null
    fi
}

function clone_dir {
    if [ ! -d "$1" ]; then
        echo -e "\e[32mCloning branch $3 of $2 in $1\e[39m"
        git clone -b "$3" "$2" "$1"
        if [ $? -ne 0 ]; then
            echo -e "\e[91mError cloning $1\e[39m"
        fi
        if [ $# -eq 4 ]; then
            pushd "$1" > /dev/null
            git checkout "$4"
            popd > /dev/null
        fi
    fi
}

function update_layer_config {
    layers_smartwatch=($(find src/meta-smartwatch -mindepth 1 -name "*meta-*" -type d | sed -e 's|src/||' | sort))
    layers=("${layers_conf[@]}" "${layers_smartwatch[@]}")
    for l in "${layers[@]}"; do
        layer_line="  \${SRCDIR}/${l} \\\\"
        awk -i inplace -v line="$layer_line" -v l="$l" '
        FNR==NR { if($0~l) { found=1 } next }
        /BBLAYERS/ && found=="" { print $0 ORS line; next }
        1
        ' build/conf/bblayers.conf build/conf/bblayers.conf
    done
}

if [[ "$1" == "update" ]]; then
    pull_dir . master
    for l in "${layers[@]}"; do
        if [ -n "$ZSH_VERSION" ]; then
            read -A layer <<< "$l"
        else
            read -a layer <<< "$l"
        fi
        if [ -d "${layer[0]}" ]; then
            pull_dir "${layer[0]}" "${layer[2]}"
        fi
    done
    update_layer_config
elif [[ "$1" == "git-"* ]]; then
    base=$(dirname "$0")
    gitcmd=${1:4}
    shift
    for d in "$base" "$base/src/"* "$base/src/oe-core/bitbake"; do
        if [ $(git -C "$d" "$gitcmd" "$@" | wc -c) -ne 0 ]; then
            echo -e "\e[35mgit -C $d $gitcmd $@ \e[39m"
            git -C "$d" "$gitcmd" "$@"
        fi
    done
else
    mkdir -p src build/conf

    if [ "$#" -gt 0 ]; then
        valid=false
        for device in "${devices[@]}"; do
            [[ "$1" == "$device" ]] && valid=true
        done

        if [[ "$valid" == true ]]; then
            export MACHINE="$1"
        else
            printNoDeviceInfo
            return 1
        fi
    else
        printNoDeviceInfo
        return 1
    fi

    for l in "${layers[@]}"; do
        if [ -n "$ZSH_VERSION" ]; then
            read -A layer <<< "$l"
        else
            read -a layer <<< "$l"
        fi
        clone_dir "${layer[0]}" "${layer[1]}" "${layer[2]}" "${layer[3]}"
    done

    if [ ! -e build/conf/local.conf ]; then
        echo -e "\e[32mWriting build/conf/local.conf\e[39m"
        cat <<EOF > build/conf/local.conf
DISTRO = "asteroid"
PACKAGE_CLASSES = "package_ipk"
EOF
    fi

    if [ ! -e build/conf/bblayers.conf ]; then
        echo -e "\e[32mWriting build/conf/bblayers.conf\e[39m"
        cat <<EOF > build/conf/bblayers.conf
BBPATH = "\${TOPDIR}"
SRCDIR = "\${@os.path.abspath(os.path.join("\${TOPDIR}", "../src/"))}"

BBLAYERS = " \\
EOF
        update_layer_config
    fi

    cd src/oe-core || exit
    . ./oe-init-build-env ../../build > /dev/null

    echo "Welcome to the Asteroid compilation script.

If you meet any issues you can report them to the project's GitHub page:
    https://github.com/AsteroidOS

You can now run the following command to get started with the compilation:
    bitbake asteroid-image

Have fun!"
fi
