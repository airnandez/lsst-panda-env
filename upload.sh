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
    echo -e "   ${scriptName} <tar file> <remote location> "
    echo -e "   \ne.g. ${scriptName} /path/to/file.tar.gz rubin:software/cvmfs/sw.lsst.eu/almalinux-x86_64/panda_env/v1.0.16.tar.gz"
}

#
# Parse command line
#
localTarFile=$1
remoteLocation=$2
if [[ -z ${localTarFile} || -z ${remoteLocation} ]]; then
    usage ${scriptName}
    exit 1
fi
if [[ ! -f ${localTarFile} ]]; then
    perror "could not find tar file ${localTarFile}"
    exit 1
fi

#
# We need the rclone credentials for the upload to succeed or a
# $HOME/.rclone.conf file
#
if [ -z "${RCLONE_CREDENTIALS}" ] && [ ! -f "$HOME/.rclone.conf" ]; then
    perror "environment variable RCLONE_CREDENTIALS not set or empty and $HOME/.rclone.conf not found"
    exit 1
fi

trace "uploading ${localTarFile} to ${remoteLocation}"

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
trap "rm -rf ${TMPDIR}" EXIT

#
# Download rclone executable
#
if [ ${os} == "linux" ]; then
    case $(architecture) in
        "x86_64")
            rcloneUrl="https://downloads.rclone.org/rclone-current-linux-amd64.zip"
            ;;

        "aarch64")
            rcloneUrl="https://downloads.rclone.org/rclone-current-linux-arm64.zip"
            ;;

        *)
            perror "could not determine what rclone release to download for this host architecture"
            exit 1
            ;;
    esac
elif [ ${os} == "darwin" ]; then
    case $(architecture) in
        "x86_64")
            rcloneUrl="https://downloads.rclone.org/rclone-current-osx-amd64.zip"
            ;;

        "arm64")
            rcloneUrl="https://downloads.rclone.org/rclone-current-osx-arm64.zip"
            ;;

        *)
            perror "could not determine what rclone release to download for this host architecture"
            exit 1
            ;;
    esac
fi

rcloneZipFile=${TMPDIR}/rclone-current.zip
rm -f ${rcloneZipFile}
curl -s -L -o ${rcloneZipFile} ${rcloneUrl}
if [ $? -ne 0 ]; then
    perror "error downloading rclone"
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
    perror "could not find rclone executable under ${unzipDir}"
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
cmd="${rcloneExe} -I --config ${rcloneConfFile} copyto ${localTarFile} ${remoteLocation}"
trace ${cmd}
${cmd}
rc=$?
if [ ${rc} -ne 0 ]; then
    trace "ERROR upload of ${localTarFile} to ${remoteLocation} failed"
else
    trace "upload of ${localTarFile} to ${remoteLocation} succeeded"
fi

exit ${rc}