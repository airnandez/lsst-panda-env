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
cvmfsRepo=${defaultCvmfsRepo}
productName=${defaultProductName}
forceDeployment=false
isExperimental=false
compress=true
debug=false
scratchDir='/mnt/scratch'
arch="x86_64"
distribution="almalinux"

#
# Functions
#
function usage() {
    local scriptName=$1
    echo -e "Usage:\n"
    echo -e "   ${scriptName} -h"
    echo -e "   ${scriptName} -v <version> [-p <product>] [-r <cvmfs repo>] [-F] [-X] [-D]"
    echo -e "\nExample:\n"
    echo -e "   ${scriptName} -v v1.0.16  -p ${productName} -r ${cvmfsRepo}"
    echo -e "\nOptions:\n"
    echo -e "   -D: run in debug mode"
    echo -e "   -F: force deployment even if the specified version is already deployed"
    echo -e "   -X: deploy experimental version (i.e. '-dev')"
}

#
# Parse command line
#
OPTIND=1
while getopts "ha:r:p:v:DFXS:" option; do
    case "${option}" in
        h|\?)
            usage ${scriptName}
            exit 0
            ;;
        a)
            arch=$OPTARG
            ;;
        S)
            distribution=$(echo ${OPTARG} | tr '[:upper:]' '[:lower:]')
            ;;
        r)
            cvmfsRepo=$OPTARG
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
        F)
            forceDeployment=true
            ;;
        X)
            isExperimental=true
            ;;
    esac
done
shift $((OPTIND-1))

#
# Check command line arguments
#
if [ -z ${version} ]; then
    usage ${scriptName}
    exit 1
fi
version=$(canonicalizeVersion ${version})

#
# Validate distribution
#
case ${distribution} in
    "almalinux"|"darwin"|"linux")
        ;;

    *)
        perror "unsupported distribution \"${distribution}\" (expecting \"almalinux\", \"darwin\" or \"linux\")"
        exit 1
        ;;
esac

#
# Validate architecture
#
case ${arch} in
    "aarch64"|"arm64"|"x86_64")
        ;;
    *)
        perror "unsupported architecture \"${arch}\" (expecting \"aarch64\", \"arm64\" or \"x86_64\")"
        exit 1
        ;;
esac

#
# Ensure the target cvmfs repository exists
#
if [ ! -d ${cvmfsRepo} ]; then
    echo "${scriptName}: could not find directory ${cvmfsRepo}"
    exit 1
fi

#
# Ensure this release is not yet published, unless force is true
#
deployDir=$(getInstallDir ${cvmfsRepo} ${distribution} ${arch} ${productName} ${version} ${isExperimental})
if [[ -e ${deployDir} && ${forceDeployment} == false ]]; then
    perror "${deployDir} already exists. Aborting deployment."
    exit 1
fi

#
# Prepare the target deploy directory for this release
#
if ! sudo mkdir -p ${deployDir}; then
    perror "could not create target deploy directory ${deployDir}"
    exit 1
fi

#
# Prepare a directory for downloading the archive file
#
if [[ -d '/cvmfs/tmp' ]]; then
    workDir='/cvmfs/tmp'
    trap "sudo rm -rf ${workDir}/*" EXIT
else
    workDir=$(mktemp --directory --tmpdir=${scratchDir} panda_env-deploy-XXXXXXX)
    if [[ $? != 0 ]]; then
        perror "could not create temporary work directory"
        exit 1
    fi

    # Remove work directory when not in debug mode
    [ ${debug} == false ] && trap "rm -rf ${workDir}" EXIT
fi
downloadDir="${workDir}/download/${productName}"
if ! mkdir -p ${downloadDir}; then
    perror "could not create download directory ${downloadDir}"
    exit 1
fi

#
# Download the archive file from its location in the archive to the download
# directory
#
tarFileName=$(getTarFileName ${version} ${isExperimental} ${compress})
archiveLocation=$(getArchiveLocation ${defaultBucket} ${deployDir} ${tarFileName})
downloadTarFile="${downloadDir}/${tarFileName}"
cmd="rclone copyto ${archiveLocation} ${downloadTarFile}"
trace ${cmd}; ${cmd}
if [[ ! -f ${downloadTarFile} ]]; then
    perror "could not download the archive from the store"
    exit 1
fi

#
# Extract the archive contents into download directory.
#
cmd="tar --directory ${downloadDir} -zxf ${downloadTarFile}"
trace ${cmd}; ${cmd}
if [[ $? != 0 ]]; then
    perror "${scriptName}: could not extract contents from archive file ${downloadTarFile}"
    exit 1
fi

#
# Start cvmfs transaction
#
cvmfsServerCmd=$(command -v cvmfs_server)
if [[ -n ${cvmfsServerCmd} ]]; then
    cvmfsServerCmd="sudo ${cvmfsServerCmd}"
else
    cvmfsServerCmd="echo sudo cvmfs_server"
fi
cvmfsRepoName=$(basename ${defaultCvmfsRepo})
cmd="${cvmfsServerCmd} transaction ${cvmfsRepoName}"
trace ${cmd}; ${cmd}
if [[ $? != 0 ]]; then
	perror "could not start cvmfs_server transaction"
	exit 1
fi

#
# Copy the extracted product directory to its final deployment path
#
extractedFilePath="${downloadDir}/$(basename ${deployDir})"
cmd="sudo cp --preserve --remove-destination --recursive ${extractedFilePath} $(dirname ${deployDir})"
trace ${cmd}; ${cmd}

#
# Add the '.cvmfscatalog' file to the deployment directory, if needed
#
if [[ ! -e "${deployDir}/.cvmfscatalog" ]]; then
    cvmfscatalogFile="${deployDir}/.cvmfscatalog"
    cmd="touch ${cvmfscatalogFile}"
    trace ${cmd}; ${cmd}
    cmd="chmod u=rw,g=r,o=r ${cvmfscatalogFile}"
    trace ${cmd}; ${cmd}
fi

#
# Set the owner and permissions of the newly deployed directory
#
owner="lsstsw"
if getent passwd ${owner} > /dev/null 2>&1; then
    cmd="sudo chown ${owner}:${owner} ${deployDir}"
    trace ${cmd}; ${cmd}
fi
cmd="sudo chmod u=rwx,g=rx,o=rx ${deployDir}"
trace ${cmd}; ${cmd}

#
# Commit this cvmfs transaction
#
cmd="${cvmfsServerCmd} publish ${cvmfsRepoName}"
trace ${cmd}; ${cmd}
if [[ $? != 0 ]]; then
	trace "could not commit cvmfs transaction. Aborting"
	cmd="${cvmfsServerCmd} abort -f ${cvmfsRepoName}"
	trace ${cmd}; ${cmd}
    trace "deployment of ${productName} ${version} under ${deployDir} failed"
	exit 1
fi

trace "${productName} ${version} successfully deployed under ${deployDir}"
