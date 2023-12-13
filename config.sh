#!/bin/bash

# This file is sourced by all the scripts in this project

#
# Globals
#
defaultProductName='panda_env'

defaultCvmfsRepo='/cvmfs/sw.lsst.eu'
defaultDeployDir="${defaultCvmfsRepo}/$(platform)/${defaultProductName}"

# S3 bucket where the archives are persisted
defaultBucket="rubin:software"
