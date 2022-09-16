#!/bin/bash

#
# Init
#
scriptName=$(basename $0)
scriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
if [[ -f ${scriptDir}/lib.sh ]]; then
    source ${scriptDir}/lib.sh
fi
if [[ -f ${scriptDir}/config.sh ]]; then
    source ${scriptDir}/config.sh
fi
gitRepoURL='https://github.com/lsst-dm/panda-conf'
skipUpload=false
debug=false

function usage() {
    local scriptName=$1
    echo -e "Usage:\n"
    echo -e "   ${scriptName} -h"
    echo -e "   ${scriptName} -p <product> -v <version> -d <install dir> [-D] [-U]"
    echo -e "\nExample:\n"
    echo -e "   ${scriptName} -p panda_env -v v0.0.2 -d ${defaultDeployDir}/v0.0.2"
    echo -e "\nOptions:\n"
    echo -e "   -D: run in debug mode, i.e. keep the result of the installation"
    echo -e "   -U: don't upload the resulting archive file"
}

#
# Parse command line
#
OPTIND=1
while getopts "hd:p:v:DU" option; do
    case "${option}" in
        h|\?)
            usage ${scriptName}
            exit 0
            ;;
        d)
            installDir=$OPTARG
            ;;
        p)
            productName=$OPTARG
            ;;
        v)
            version=$OPTARG
            ;;
        D)
            debug=true
            ;;   
        U)
            skipUpload=true
            ;;   
    esac
done
shift $((OPTIND-1))

#
# Check command line options
#
if [[ -z ${productName} || -z ${version} || -z ${installDir} ]]; then
    usage ${scriptName}
    exit 1
fi
if [[ ! -d ${installDir} ]]; then
    perror ${scriptName} "install directory ${installDir} does not exist"
    exit 1
fi
version=$(canonicalizeVersion ${version})

#
# Install from git repository
#
trace "installing ${productName} ${version} to ${installDir}"

#
# Prepare a temporary work directory for downloading the installer and for
# creating the tar file after the installation is successfully finished
#
scratchDir=${TMPDIR:-/tmp}
[[ -d /scratch ]] && scratchDir='/scratch'
workDir=$(mktemp --directory --tmpdir=${scratchDir} "tmp-XXXXXXX")
if [[ $? != 0 ]]; then
    perror ${scriptName} "could not create temporary directory under ${scratchDir}"
    exit 1
fi
if [ ${debug} == false ]; then
    # Remove work directory when not in debug mode
    trap "rm -rf ${workDir}" EXIT
fi

#
# Download to our work directory the panda-env installer for the specified release 
#
downloadDir="${workDir}/download"
mkdir -p ${downloadDir}
archiveName="${version}.tar.gz"
url="${gitRepoURL}/archive/refs/tags/${archiveName}"
wget --quiet --directory-prefix ${downloadDir} ${url}
if [[ $? != 0 ]]; then
    perror ${scriptName} "could not download panda_env version ${version}"
    exit 1
fi

#
# Unpack the installer and run the installer. A directory named like
# "panda-conf-x.x.x" will be created. That directory contains the installer
# which is named "panda_env/panda_env_install.sh"
#
trace "unpacking the installer"
tar --directory ${downloadDir} -zxf "${downloadDir}/${archiveName}"

trace "installing ${productName} ${version} in directory ${installDir}"
installer=$(readlink -f ${downloadDir}/panda-conf-*/panda_env/panda_env_install.sh)
if [[ ! -f ${installer} ]]; then
    perror ${scriptName} "could not find installer panda_env_install.sh"
    exit 1
fi

trace "runing the installer with install directory ${installDir}"
bash ${installer} ${installDir}
rc=$?
if [[ ${rc} != 0 ]]; then
    perror ${scriptName} "execution of panda_env installer failed (rc=${rc})"
    exit 1
fi

#
# Create an archive file for this version relative to the top install directory
#
archiveDir="${workDir}/archive"
mkdir -p ${archiveDir}
tarFileName=$(getArchiveNameForDir ${installDir})
archiveFileName="${archiveDir}/${tarFileName}"

trace "writing tar file to ${archiveFileName}"
tar --hard-dereference \
    --directory $(dirname ${installDir}) \
    -zcf ${archiveFileName} \
    ./$(basename ${installDir})

#
# Upload the archive file to the persistent location
#
if [ ${skipUpload} == false ]; then
    ${scriptDir}/upload.sh ${productName} ${archiveFileName}
fi

#
# Done
#
trace "installation of ${productName} ${version} in ${installDir} finished successfully"
exit 0