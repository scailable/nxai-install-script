#!/usr/bin/env bash

###############################################################################
# Instructions
#
# Step 1: Set environment variables:
#   source set_nxai_installer.sh
#
# Step 2: Install and configure NxAI:
#   sudo -E bash run_nxai_installer.sh
#
# To run both steps in a single command:
#   source set_nxai_installer.sh && sudo -E bash run_nxai_installer.sh
###############################################################################

###############################################################################
# Set Environment Variables (required)
###############################################################################

 export NX_CLOUD_USER=""
 export NX_CLOUD_PASS=""
 export NX_SYSTEM_NAME=""
 export LOCAL_PASSWORD_NEW=""

###############################################################################
# Optional environment variables
###############################################################################

# 0000-0000-0000-0029 is the NX Meta trial license key
 export SYSTEM_LICENSE_KEY="0000-0000-0000-0029"

# Nx Local Settings
export ENABLE_AI_PLUGIN=true
export ENABLE_SAME_NAME_SYSTEM_MERGE=true
export ENABLE_DEVICE_RECORDING=true

# Cloud Credentials & Connectivity
export NX_CLOUD_HOST="meta.nxvms.com"
export NX_CLOUD_URL="https://${NX_CLOUD_HOST}"

# Local Credentials & Connectivity
 export LOCAL_LOGIN="admin"
 export LOCAL_PASSWORD="admin"
export LOCAL_SERVER_URL="https://localhost:7001"

# Nx Server Download & Package URLs
export NX_SERVER_DOWNLOAD_URL="https://updates.networkoptix.com/metavms/39873/linux/metavms-server-6.0.1.39873-linux_x64.deb"
export NX_AI_PLUGIN_VERSION="nightly"
export NX_AI_PLUGIN_INSTALL_URL="https://artifactory.nxvms.dev/artifactory/nxai_open/NXAIPlugin/install.sh"
export NX_AI_PLUGIN_DOWNLOAD_URL="https://artifactory.nxvms.dev/artifactory/nxai_open/NXAIManager/v4-1/nxai_manager-x86_64.tgz"
export NX_AI_OAAX_RUNTIME_DOWNLOAD_URL="https://artifactory.nxvms.dev/artifactory/nxai_open/OAAX/runtimes/v4-1/cpu-x86_64-ort.tar.gz"

# Optional Testcamera 
export ENABLE_TESTCAMERA=false
export MOVIE_DIR="/opt/movies"
export MOVIE_URL="http://www.robinvanemden.dds.nl/walking.mp4"
export MOVIE_FILE=$(basename "$MOVIE_URL")

# Optional Stream
export ENABLE_TEST_STREAM=true
export STREAM_URL="rtsp://5.75.171.116:8554/face-blur-4-people"
export STREAM_USER=""
export STREAM_PASS="" 

# Other settings
export MAX_PLUGIN_ATTEMPTS=10
export WAIT_TIMEOUT=60
export RESPONSE_EXPIRATION_TIMEOUT_S=10
