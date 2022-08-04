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
    local prefix=$1
    shift 1
    printf "%s: %s\n" "${prefix}" "$*" >&2
}

# Canonicalize version to the form: "v1.2.3"
function canonicalizeVersion() {
    local version=$1
    # Strip 'v' prefix
    version=$(echo ${version} | tr [:upper:] [:lower:] | sed -e 's/^[v]*//')
    echo "v${version}"
}

# Returns the operating system, e.g. "linux", "darwin"
function osName() {
    echo $(uname -s | tr [:upper:] [:lower:])
}

# Returns an identifier for the running platform, e.g. "linux-x86_64"
function platform() {
    # Get the kernel architecture, e.g. "x86_64"
    local arch=$(uname -m | tr [:upper:] [:lower:])
    echo $(osName)-${arch}
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

# Returns the absolute path of the target deploment directory for a product,
# given the cvmfs repository, the platform (i.e. 'linux-x86_64') and
# the product name.
#
# Example: given the cvmfs repository '/cvmfs/sw.lsst.eu', the product 
# name 'panda_env' and the platform 'linux-x86_64', this function returns
#    '/cvmfs/sw.lsst.eu/linux-x86_64/panda_dev'
function getProductDeployDir() (
    local cvmfsRepo=$1
    local platform=$2
    local productName=$3
    echo -e "${cvmfsRepo}/${platform}/${productName}"
)

# Returns the absolute path of the deployment directory for a specific version
# of a product, given its product deployment directory, the product version
# and whether the version is experimental.
#
# For instace, given the product deploymebt directory
# '/cvmfs/sw.lsst.eu/linux-x86_64/panda_dev', the version 'v0.0.2' it retunrs
#    '/cvmfs/sw.lsst.eu/linux-x86_64/panda_dev/v0.0.2'
# If this is an experimental version, the functions returns instead
#    '/cvmfs/sw.lsst.eu/linux-x86_64/panda_dev/v0.0.2-dev'
function getProductVersionDeployDir() {
    local productDeployDir=$1
    local productVersion=$2
    local isExperimental=$3
    if [[ ${isExperimental} == true ]]; then
        productVersion+="-dev"
    fi
    echo -e "${productDeployDir}/${productVersion}"
}

# Returns the name of a tar file for a directory deployed at path.
#
# For instance, when this function is called called with argument
#    '/cvmfs/sw.lsst.eu/linux-x86_64/panda_dev/v0.0.2'
#  it returns
#    'cvmfs__sw.lsst.eu__linux-x86_64__panda_env__v0.0.2-dev.tar.gz'
function getArchiveNameForDir() {
    local dir=$1
    echo $(echo ${dir}.tar.gz | cut -b 2- | sed -e 's|/|__|g')
}

# Returns the location of an archive file given its bucket, platform for
# which the archive has been created, product name and archive name.
#
# For instance, when this function is called with bucket 'bucket',
# platform 'linux-x86_64', product 'panda_env' and archive name
# 'cvmfs__sw.lsst.eu__linux-x86_64__panda_env__v0.0.2-dev.tar.gz' it 
# returns
#   'bucket/linux-x86_64/panda_env/cvmfs__sw.lsst.eu__linux-x86_64__panda_env__v0.0.2-dev.tar.gz'
function getArchiveLocation() {
    local bucket=$1
    local platform=$2
    local product=$3
    local archiveName=$4
    echo "${bucket}/${platform}/${productName}/$(basename ${archiveName})"
}