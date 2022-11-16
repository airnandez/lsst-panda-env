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
productName=${defaultProductName}
installTopDir="${defaultCvmfsRepo}/$(platform)/${productName}"
isExperimental=false
skipUpload=false
debug=false
scratchDir='/mnt/scratch'

function usage() {
    local scriptName=$1
    echo -e "Usage:\n"
    echo -e "   ${scriptName} -h"
    echo -e "   ${scriptName} -v <version>  [-d <install top dir>] [-D] [-U] [-X]"
    echo -e "\nExamples:\n"
    echo -e "   ${scriptName} -v v0.0.2"
    echo -e "   ${scriptName} -v v0.0.2 -d ${installTopDir}"    
    echo -e "\nOptions:\n"
    echo -e "   -D: run in debug mode (keep the resulting installation)"
    echo -e "   -U: don't upload the resulting archive file"
    echo -e "   -X: experimental build (i.e. '-dev')"
}

#
# Parse command line
#
OPTIND=1
while getopts "hd:v:DUX" option; do
    case "${option}" in
        h|\?)
            usage ${scriptName}
            exit 0
            ;;
        d)
            installTopDir=$OPTARG
            ;;
        v)
            pandaEnvVersion=$OPTARG
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
# Check options
#
if [[ -z ${pandaEnvVersion} ]]; then
    usage ${scriptName}
    exit 1
fi

#
# Build the Docker image with all the prerequisites to install panda_env
#
trace "preparing Docker image"
pandaEnvVersion=$(canonicalizeVersion ${pandaEnvVersion})
imageName="rubin/panda_env:${pandaEnvVersion}"
DOCKER_SCAN_SUGGEST=false
imageID=$(docker build --network host --quiet --tag ${imageName} .)
rc=$?
if [[ $rc != 0 ]]; then
    perror ${scriptName} "could not build Docker image"
    exit 1
fi

#
# Run the Docker image to execute the panda-env installer. Expose this
# script's directory to the container under the mount point '/work'
#
workDir=$(mktemp --directory --tmpdir=${scratchDir} panda_env-install-XXXXXXX)
if [[ $? != 0 ]]; then
    perror ${scriptName} "could not create temporary work directory"
    exit 1
fi

# Don't remove work directory (for debugging purposes) when executing in
# debug mode
if [ ${debug} == false ]; then
    trap "rm -rf ${workDir}" EXIT
fi

# 
# Prepare install command line (file paths are in container name space)
#
installDir="${installTopDir}/${pandaEnvVersion}"
[ ${isExperimental} == true ] && installDir="${installDir}-dev"

installCommand="/work/install-panda-env.sh"
installFlags="-p ${productName} -v ${pandaEnvVersion} -d ${installDir}"
[ ${skipUpload} == true ] && installFlags+=" -U "
[ ${debug} == true ] && installFlags+=" -D "
installCommand+=" ${installFlags}"

#
# Run the Docker image to execute the panda-env installer. Expose this
# script's directory to the container under the mount point '/work',
# a scratch directory as '/scratch' and the temporary install directory
# as the requested target installation directory.
#
docker run \
    --rm \
    --privileged \
    --network host \
    --volume $(pwd):/work \
    --volume ${scratchDir}:/scratch \
    --volume ${workDir}:${installDir} \
    --env RCLONE_CREDENTIALS=$(base64Encode $HOME/.rclone.conf) \
    ${imageName} \
    ${installCommand}

if [[ $? != 0 ]]; then
    perror ${scriptName} "could not install panda_env"
    exit 1
fi

exit 0
