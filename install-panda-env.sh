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
isExperimental=false
compress=true

function usage() {
    local scriptName=$1
    echo -e "Usage:\n"
    echo -e "   ${scriptName} -h"
    echo -e "   ${scriptName} -p <product> -v <version> -d <install dir> [-D] [-U]"
    echo -e "\nExample:\n"
    echo -e "   ${scriptName} -p panda_env -v v0.0.2 -d ${defaultInstallTopDir}"
    echo -e "\nOptions:\n"
    echo -e "   -D: run in debug mode, i.e. keep the result of the installation"
    echo -e "   -U: don't upload the resulting archive file"
}

#
# Parse command line
#
OPTIND=1
while getopts "hd:p:v:DUX" option; do
    case "${option}" in
        h|\?)
            usage ${scriptName}
            exit 0
            ;;
        d)
            installTopDir=$OPTARG
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
        X)
            isExperimental=true
            ;;
    esac
done
shift $((OPTIND-1))

#
# Check command line options
#
if [[ -z ${productName} || -z ${version} || -z ${installTopDir} ]]; then
    usage ${scriptName}
    exit 1
fi
if [[ ! -d ${installTopDir} ]]; then
    perror "install directory ${installTopDir} does not exist"
    exit 1
fi
version=$(canonicalizeVersion ${version})

#
# Prepare install directory
#
installDir=$(getInstallDir ${installTopDir} $(osDistrib) $(architecture) ${productName} ${version} ${isExperimental})
trace "installing ${productName} ${version} to ${installDir}"

#
# Prepare a temporary work directory for downloading the installer and for
# creating the tar file after the installation is successfully finished
#
scratchDir=${TMPDIR:-/tmp}
[[ -d /scratch ]] && scratchDir='/scratch'
workDir=$(mktemp --directory --tmpdir=${scratchDir} "tmp-XXXXXXX")
if [[ $? != 0 ]]; then
    perror "could not create temporary directory under ${scratchDir}"
    exit 1
fi
if [ ${debug} == false ]; then
    # Remove work directory when not in debug mode
    trap "rm -rf ${workDir}" EXIT
fi

#
# Download the panda-env installer for the specified release to our work
# directory.
#
downloadDir="${workDir}/download"
if ! mkdir -p ${downloadDir}; then
    perror "could not create directory ${downloadDir}"
    exit 1
fi
remoteArchiveName="${version}.tar.gz"
url="${gitRepoURL}/archive/refs/tags/${remoteArchiveName}"
wget --quiet --directory-prefix ${downloadDir} ${url}
if [[ $? != 0 ]]; then
    perror "could not download panda_env version ${version}"
    exit 1
fi

#
# Unpack and run the installer. A directory named like "panda-conf-x.x.x" will
# be created. That directory contains the installer which is named
# "panda_env/panda_env_install.sh"
#
trace "unpacking the installer"
tar --directory ${downloadDir} -zxf "${downloadDir}/${remoteArchiveName}"

trace "installing ${productName} ${version} in directory ${installDir}"
installer=$(readlink -f ${downloadDir}/panda-conf-*/panda_env/panda_env_install.sh)
if [[ ! -f ${installer} ]]; then
    perror "could not find installer ${installer}"
    exit 1
fi

trace "runing the installer with install directory ${installDir}"
bash ${installer} ${installDir}
rc=$?
if [[ ${rc} != 0 ]]; then
    perror "execution of panda_env installer failed (rc=${rc})"
    exit 1
fi

#
# Create an tar file for this version
#
archiveDir="${workDir}/archive"
if ! mkdir -p ${archiveDir}; then
    perror "could not create archive directory ${archiveDir}"
    exit 1
fi
tarFileName=$(getTarFileName ${version} ${isExperimental} ${compress})
archiveFileName="${archiveDir}/${tarFileName}"
trace "writing tar file to ${archiveFileName}"
tar --hard-dereference \
    --directory $(dirname ${installDir}) \
    -zcf ${archiveFileName} \
    ./$(basename ${installDir})

#
# Upload the tar file to the archive
#
if [[ ${skipUpload} == false ]]; then
    archiveLocation=$(getArchiveLocation ${defaultBucket} ${installDir} ${tarFileName})
    ${scriptDir}/upload.sh ${archiveFileName} ${archiveLocation}
else
    trace "skipping upload of archive file ${archiveFileName}"
fi

#
# Done
#
trace "installation of ${productName} ${version} in ${installDir} finished successfully"
exit 0