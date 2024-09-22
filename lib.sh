#!/bin/bash

# This file is sourced by all the scripts in this project

#
# Functions
#

# Sends a timestamped message to stdout
function trace() {
    local prefix=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    [ -n ${scriptName} ] && prefix+=" ${scriptName}:"
    echo -e ${prefix} $*
}

# Writes a message to standard error
function perror() {
    local prefix=""
    [ -n ${scriptName} ] && prefix="${scriptName}:"
    echo "${prefix} ERROR -" "$*" >&2
}

# Canonicalize version to the form: "v1.2.3"
function canonicalizeVersion() {
    local version=$1
    # Strip 'v' prefix
    version=$(echo ${version} | tr '[:upper:]' '[:lower:]' | sed -e 's/^[v]*//')
    echo "v${version}"
}

# Returns the operating system, e.g. "linux", "darwin"
function osName() {
    echo $(uname -s | tr '[:upper:]' '[:lower:]')
}

# Returns an identifier for the running platform, e.g. "linux-x86_64"
function platform() {
    echo $(osName)-$(architecture)
}

# Returns the architecture, e.g. "x86_64", "arm64", "aarch64"
function architecture() {
    echo $(uname -m | tr '[:upper:]' '[:lower:]')
}

# Returns the specific distribution of the operating system e.g. "almalinux",
# "rhel", "darwin".
function osDistrib() {
    local distrib
    case $(osName) in
        "darwin")
            distrib="darwin"
            ;;

        "linux")
            distrib="unknownlinux"
            if [[ -f "/etc/os-release" ]]; then
                # File '/etc/os-release' contains a line of the form 'ID="almalinux"'. Extract the Linux identifier.
                distrib=$(cat /etc/os-release | awk -F '=' '$1=="ID" {print $2}' | sed 's/"//g' | tr '[:upper:]' '[:lower:]')
            fi
            ;;

        *)
            ;;
    esac
    echo "${distrib}"
}

# Returns the specific distribution of the operating system and the architecture
# e.g. "almalinux-aarch64", "rhel-x86_64", "darwin-x86_64"
function osDistribArch() {
    echo "$(osDistrib)-$(architecture)"
}

# Encodes the contents of a file in base 64
function base64Encode() {
    local path=$1
    local result=""
    if [[ $(osName) == "darwin" ]]; then
        result=$(cat ${path} | base64)
    else
        result=$(cat ${path} | base64 -w 0)
    fi
    echo ${result}
}

# Returns the location of an archive file given its bucket, installation
# directory and tar filename.
#
# For instance, when this function is called with bucket 'bucket',
# installDir '/cvmfs/sw.lsst.eu/linux-x86_64/panda_env/v1.0.16' and
# tarFileName 'v1.0.16.tar.gz' it returns
#   'bucket/cvmfs/sw.lsst.eu/linux-x86_64/panda_env/v1.0.16.tar.gz'
function getArchiveLocation() {
    local bucket=$1
    local installDir=$2
    local tarFileName=$3

    echo "${bucket}$(dirname ${installDir})/$(basename ${tarFileName})"
}

# Returns the name of the tar file for a given version.
#
# For instance, when this function is called with version 'v1.0.16',
# isExperimental 'false' and compress 'true' it returns 'v1.0.16.tar.gz'.
#
# If called with isExperimental 'false' it returns 'v1.0.16-dev.tar.gz'.
function getTarFileName() {
    local version=$(canonicalizeVersion $1)
    local isExperimental=$2
    local compress=$3
    local result=${version}
    [[ ${isExperimental} == true ]] && result="${result}-${defaultExperimentalSuffix}"
    if [[ ${compress} == true ]]; then
        echo "${result}.tar.gz"
    else
        echo "${result}.tar"
    fi
}

# Returns the full path of the installation directory.
#
# For instance, when this function is called with installTopDir '/cvmfs/sw.lsst.eu'
# distrib 'almalinux', architecture 'x86_64', product 'panda_env', version
# 'v1.0.16', isExperimental 'false' it returns
#    '/cvmfs/sw.lsst.eu/almalinux-x86_64/panda_env/v1.0.16'
function getInstallDir() {
    local installTopDir=$1
    local distrib=$2
    local architecture=$3
    local product=$4
    local version=$(canonicalizeVersion $5)
    local isExperimental=$6

    local result="${installTopDir}/${distrib}-${architecture}/${product}/${version}"
    if [[ ${isExperimental} == true ]]; then
        echo "${result}-${defaultExperimentalSuffix}"
    else
        echo "${result}"
    fi
}
