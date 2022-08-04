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

#
# Functions
#
function usage() {
    local scriptName=$1
    echo -e "Usage:\n"
    echo -e "   ${scriptName} <product> <archive file>"
    echo -e "   \ne.g. ${scriptName} panda_env /path/to/file.tar.gz"
}

#
# Parse command line
#
productName=$1
tarFilePath=$2
if [[ -z ${productName} || -z ${tarFilePath} ]]; then
    usage ${scriptName}
    exit 1
fi
if [[ ! -f ${tarFilePath} ]]; then
    perror ${scriptName} "could not find tar file ${tarFilePath}"
    exit 1
fi

#
# We need the rclone credentials for the upload to succeed or a
# $HOME/.rclone.conf file
#
if [ -z "${RCLONE_CREDENTIALS}" ] && [ ! -f "$HOME/.rclone.conf" ]; then
    perror ${scriptName} "environment variable RCLONE_CREDENTIALS not set or empty and $HOME/.rclone.conf not found"
    exit 1
fi

trace "${scriptName}: uploading ${productName} tar file at ${tarFilePath}"

#
# Prepare temporary directory for downloading rclone package
#
os=$(osName)
USER=${USER:-$(id -un)}
TMPDIR=${TMPDIR:-"/tmp"}
mkdir -p ${TMPDIR}
if [ ${os} == "darwin" ]; then
    TMPDIR=$(mktemp -d ${TMPDIR}/${USER}.upload.XXXXX)
else
    TMPDIR=$(mktemp --directory --tmpdir=${TMPDIR} ${USER}.upload.XXXXX)
fi
trace "TMPDIR=${TMPDIR}"
trap "rm -rf ${TMPDIR}" EXIT

#
# Download rclone executable
#
rcloneUrl="https://downloads.rclone.org/rclone-current-linux-amd64.zip"
if [ $(osName) == "darwin" ]; then
    rcloneUrl="https://downloads.rclone.org/rclone-current-osx-amd64.zip"
fi
rcloneZipFile=${TMPDIR}/$(basename ${rcloneUrl})
rm -f ${rcloneZipFile}
curl -s -L -o ${rcloneZipFile} ${rcloneUrl}
if [ $? -ne 0 ]; then
    perror ${scriptName} "error downloading rclone"
    exit 1
fi

#
# Unpack rclone and make it ready for execution
#
unzipDir=${TMPDIR}/rclone
rm -rf ${unzipDir}
unzip -qq -d ${unzipDir} ${rcloneZipFile}
rcloneExe=$(find ${unzipDir} -name rclone -type f -print)
if [[ ! -f ${rcloneExe} ]]; then
    perror ${scriptName} "could not find rclone executable under ${unzipDir}"
    exit 1
fi
chmod u+x ${rcloneExe}

#
# Create a rclone.conf file with appropriate permissions
#
if [ -f "$HOME/.rclone.conf" ]; then
    rcloneConfFile="$HOME/.rclone.conf"
    eraseRcloneConf="false"
else
    eraseRcloneConf="true"
    rcloneConfFile=${TMPDIR}/.rclone.conf
    echo ${RCLONE_CREDENTIALS} | base64 -d > ${rcloneConfFile} && chmod g-rwx,o-rwx ${rcloneConfFile}
fi

#
# Upload the archive file to its location in the persistent store
#
storeLocation=$(getArchiveLocation ${defaultBucket} $(platform) ${productName} ${tarFilePath})
trace "${scriptName}: uploading archive file ${tarFilePath} to ${storeLocation}"
cmd="${rcloneExe} -I --config ${rcloneConfFile} copyto ${tarFilePath} ${storeLocation}"
trace ${cmd}
${cmd}
rc=$?
if [ ${rc} -ne 0 ]; then
    trace "${scriptName}: ERROR upload failed"
    exit ${rc}
fi

trace "${scriptName}: upload succeeded"
exit 0
