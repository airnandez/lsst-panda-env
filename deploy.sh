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
debug=false
scratchDir='/mnt/scratch'

#
# Functions
#
function usage() {
    local scriptName=$1
    echo -e "Usage:\n"
    echo -e "   ${scriptName} -h"
    echo -e "   ${scriptName} -v <version> [-p <product>] [-r <cvmfs repo>] [-F] [-X] [-D]"
    echo -e "\nExample:\n"
    echo -e "   ${scriptName} -v 0.0.2  -p ${productName} -r ${cvmfsRepo}"
    echo -e "\nOptions:\n"
    echo -e "   -D: run in debug mode"
    echo -e "   -F: force deployment even if the specified version is already deployed"
    echo -e "   -X: deploy experimental version (i.e. '-dev')"
}

#
# Parse command line
#
OPTIND=1
while getopts "hr:p:v:DFX" option; do
    case "${option}" in
        h|\?)
            usage ${scriptName}
            exit 0
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
# Ensure the target cvmfs repository exists
#
if [ ! -d ${cvmfsRepo} ]; then
    echo "${scriptName}: could not find directory ${cvmfsRepo}"
    exit 1
fi
cvmfsRepo=$(readlink -f ${cvmfsRepo})

#
# Ensure this release is not yet published, unless force is true
#
productDeployDir=$(getProductDeployDir ${cvmfsRepo} $(platform) ${productName})
productVersionDeployDir=$(getProductVersionDeployDir ${productDeployDir} ${version} ${isExperimental})
if [[ -e ${productVersionDeployDir} && ${forceDeployment} == false ]]; then
    echo "${scriptName}: ${productVersionDeployDir} already exists. Aborting deployment."
    exit 1
fi

#
# Prepare the target deploy directory for this release
#
mkdir -p ${productDeployDir}
if [[ $? -ne 0 ]]; then
    echo "${scriptName}: could not create target deploy directory ${productDeployDir}"
    exit 1
fi

#
# Prepare a directory for downloading the archive file
#
if [[ -d '/cvmfs/tmp' ]]; then
    workDir='/cvmfs/tmp'
    trap "sudo rm -f ${workDir}/*" EXIT
else
    workDir=$(mktemp --directory --tmpdir=${scratchDir} panda_env-deploy-XXXXXXX)
    if [[ $? != 0 ]]; then
        perror ${scriptName} "could not create temporary work directory"
        exit 1
    fi
    # Remove work directory when not in debug mode
    [ ${debug} == false ] && trap "rm -rf ${workDir}" EXIT
fi
downloadDir=${workDir}/download
mkdir -p ${downloadDir}

#
# Download the archive file from its location in the persistent store to
# the download directory
#
canonicalProductDeployDir=$(getProductDeployDir ${defaultCvmfsRepo} $(platform) ${productName})
canonicalProductVersionDeployDir=$(getProductVersionDeployDir ${canonicalProductDeployDir} ${version} ${isExperimental})
archiveName=$(getArchiveNameForDir ${canonicalProductVersionDeployDir})
archiveLocation=$(getArchiveLocation ${defaultBucket} $(platform) ${productName} ${archiveName})

cmd="rclone copy ${archiveLocation} ${downloadDir}"
trace ${cmd}; ${cmd}
if [[ ! -f ${downloadDir}/${archiveName} ]]; then
    perror ${scriptName} "could not download the archive from the store"
    exit 1
fi

#
# Extract the archive contents into download directory.
#
cmd="tar --directory ${downloadDir} -zxf ${downloadDir}/${archiveName}"
trace ${cmd}; ${cmd}
if [[ $? != 0 ]]; then
    perror "${scriptName}: could not extract contents from archive file ${downloadDir}/${archiveName}"
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
	perror ${scriptName} "could not start cvmfs_server transaction"
	exit 1
fi

#
# Copy the extracted product directory to its final deployment path
#
extractedFilePath=${downloadDir}/$(basename ${productVersionDeployDir})
cmd="sudo cp --preserve --remove-destination --recursive ${extractedFilePath} ${productDeployDir}"
trace ${cmd}; ${cmd}

#
# Add the '.cvmfscatalog' file to the deployment directory, if needed
#
if [[ ! -e ${productVersionDeployDir}/.cvmfscatalog ]]; then
    cvmfscatalogFile="${productVersionDeployDir}/.cvmfscatalog"
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
    cmd="sudo chown ${owner}:${owner} ${productVersionDeployDir}"
    trace ${cmd}; ${cmd}
fi
cmd="sudo chmod u=rwx,g=rx,o=rx ${productVersionDeployDir}"
trace ${cmd}; ${cmd}

#
# Commit this cvmfs transaction
#
cmd="${cvmfsServerCmd} publish ${cvmfsRepoName}"
trace ${cmd}; ${cmd}
if [[ $? != 0 ]]; then
	echo "${scriptName}: could not commit cvmfs transaction. Aborting"
	cmd="${cvmfsServerCmd} abort -f ${cvmfsRepoName}"
	trace ${cmd}; ${cmd}
	exit 1
fi

trace "deployment of ${productName} ${version} under ${productVersionDeployDir} finished successfully"
