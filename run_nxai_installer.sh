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
#
# This script automates installing and configuring Network Optix (Nx) software:
#
#   1) Installs dependencies and the Nx server (checks connectivity, sets OS info).
#   2) Authenticates, sets up the Nx system, and registers a license.
#   3) Installs Nx AI plugin, OAAX runtime, and, optional, a stream or testcamera.
#   4) Turns on minimal recording of on all cameras (that is, all "devices").
#   4) Connects to Nx Cloud and merges multiple Nx systems
#      sharing the same name in the Cloud.
#
###############################################################################

# Use a special IFS setting to avoid issues with word splitting:
#   - This helps handle filenames or other parameters with spaces/new lines
IFS=$'\n\t'

# Enforce that the script must be run as root, since installation steps
# and service restarts require elevated privileges.
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Exiting."
    exit 1
fi

# Print an empty line at the start of the script
echo

# Use a trap to ensure an empty line is printed on exit
trap 'echo' EXIT

###############################################################################
# Required Environmental Variables
###############################################################################

# Define required variables
required_vars=(
    NX_CLOUD_USER
    NX_CLOUD_PASS
    NX_SYSTEM_NAME
    LOCAL_PASSWORD_NEW
)

# Initialize a flag to track missing variables
missing_vars=()
short_password_vars=()

# Check for unset required variables
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    elif [[ "$var" == "NX_CLOUD_PASS" || "$var" == "LOCAL_PASSWORD_NEW" ]]; then
        # Check for password length
        if [ "${#var}" -lt 8 ]; then
            short_password_vars+=("$var")
        fi
    fi
done

# If any variables are missing, list them and exit
if [ "${#missing_vars[@]}" -gt 0 ]; then
    echo -e "\033[1;31mERROR:\033[0m The following required environment variables are not set:"
    echo "--------------------------------------------------"
    for var in "${missing_vars[@]}"; do
        echo -e "  - \033[1;33m$var\033[0m"
    done
    echo "--------------------------------------------------"
    echo -e "\033[1;31mPlease set the above environment variables\033[0m"
    echo -e "\033[1;31m(e.g., export VAR_NAME='value') and re-run this script.\033[0m"
    exit 1
fi

# If any passwords are too short, list them and exit
if [ "${#short_password_vars[@]}" -gt 0 ]; then
    echo -e "\033[1;31mERROR:\033[0m The following password variables must be at least 8 characters long:"
    echo "--------------------------------------------------"
    for var in "${short_password_vars[@]}"; do
        echo -e "  - \033[1;33m$var\033[0m"
    done
    echo "--------------------------------------------------"
    echo -e "\033[1;31mPlease update the above passwords to meet the length requirement and re-run this script.\033[0m"
    exit 1
fi

###############################################################################
# Environment Variables and Defaults
#   - Set defaults for environment variables if not already defined.
#   - Notify the user if any required variables are unset.
###############################################################################

# Cloud Credentials & Connectivity
: "${NX_CLOUD_HOST:="meta.nxvms.com"}"
: "${NX_CLOUD_URL:="https://${NX_CLOUD_HOST}"}"
: "${NX_CLOUD_USER:=""}"
if [ -z "$NX_CLOUD_USER" ]; then
    echo "Error: NX_CLOUD_USER is not set. Please set this variable."
    exit 1
fi

: "${NX_CLOUD_PASS:=""}"
if [ -z "$NX_CLOUD_PASS" ]; then
    echo "Error: NX_CLOUD_PASS is not set. Please set this variable."
    exit 1
fi

# Nx Local Settings
: "${ENABLE_AI_PLUGIN:=true}"  # Enable Nx AI Plugin
: "${ENABLE_SAME_NAME_SYSTEM_MERGE:=true}"  # Allow merging systems with the same name in Nx Cloud
: "${ENABLE_DEVICE_RECORDING:=true}"  # Enable minimal recording on all devices

: "${NX_SYSTEM_NAME:=""}"
if [ -z "$NX_SYSTEM_NAME" ]; then
    echo "Error: NX_SYSTEM_NAME is not set. Please set this variable."
    exit 1
fi

: "${SYSTEM_LICENSE_KEY:="0000-0000-0000-0029"}"  # Default system license key

# Local Nx User Credentials
: "${LOCAL_LOGIN:="admin"}"
: "${LOCAL_PASSWORD:="admin"}"
: "${LOCAL_PASSWORD_NEW:=""}"
if [ -z "$LOCAL_PASSWORD_NEW" ]; then
    echo "Error: LOCAL_PASSWORD_NEW is not set. Please set this variable."
    exit 1
fi

: "${LOCAL_SERVER_URL:="https://localhost:7001"}"  # Local Nx server URL

# Nx Server Download & Package URLs
: "${NX_SERVER_DOWNLOAD_URL:="https://updates.networkoptix.com/metavms/39873/linux/metavms-server-6.0.1.39873-linux_x64.deb"}"

: "${NX_AI_PLUGIN_VERSION:="nightly"}"
: "${NX_AI_PLUGIN_INSTALL_URL:="https://artifactory.nxvms.dev/artifactory/nxai_open/NXAIPlugin/install.sh"}"
: "${NX_AI_PLUGIN_DOWNLOAD_URL:="https://artifactory.nxvms.dev/artifactory/nxai_open/NXAIManager/v4-1/nxai_manager-x86_64.tgz"}"

: "${NX_AI_OAAX_RUNTIME_DOWNLOAD_URL:="https://artifactory.nxvms.dev/artifactory/nxai_open/OAAX/runtimes/v4-1/cpu-x86_64-ort.tar.gz"}"

# Test Camera / Stream 
: "${ENABLE_TESTCAMERA:=false}"  # Enable testcamera
: "${MOVIE_DIR:="/opt/movies"}"  # Directory to store test camera footage
: "${MOVIE_URL:="http://www.robinvanemden.dds.nl/walking.mp4"}"  # Test movie URL
: "${MOVIE_FILE:=$(basename "$MOVIE_URL")}"  # Extract the filename from the URL

: "${ENABLE_TEST_STREAM:=true}"  # Enable test stream
: "${STREAM_URL:="rtsp://5.75.171.116:8554/face-blur-4-people"}"  # Stream URL
: "${STREAM_USER:=""}"  # Stream username
: "${STREAM_PASS:=""}"  # Stream password

# Other Settings
: "${MAX_PLUGIN_ATTEMPTS:=10}"  # Maximum attempts to wait for a plugin
: "${WAIT_TIMEOUT:=60}"  # Timeout for operations in seconds
: "${RESPONSE_EXPIRATION_TIMEOUT_S:=10}"  # Expiration timeout for responses in seconds

# Suppress interactive prompts during apt-get installations
DEBIAN_FRONTEND=noninteractive

###############################################################################
# Generic Helper Functions
###############################################################################
# These functions perform repeated operations like waiting for a service
# or restarting the Nx server.

# -----------------------------------------------------------------------------
# wait_for_service
#   Usage:
#       wait_for_service "My Service" "check_command_here" TIMEOUT_SECONDS
#   Waits until 'check_command' succeeds or times out.
# -----------------------------------------------------------------------------
wait_for_service() {
    local service_name="$1"
    local check_command="$2"
    local timeout="$3"
    local elapsed_seconds=0

    echo "Waiting for $service_name to start..."
    # Loop until the check_command succeeds or we hit the timeout
    while ! eval "$check_command"; do
        sleep 1
        (( elapsed_seconds++ ))
        if [ "$elapsed_seconds" -ge "$timeout" ]; then
            echo "Error: Timed out waiting for $service_name."
            exit 1
        fi
    done
    echo "$service_name is running."
}

# -----------------------------------------------------------------------------
# wait_for_nx_server
#   Waits specifically for the Nx server to respond at LOCAL_SERVER_URL/api/ping.
# -----------------------------------------------------------------------------
wait_for_nx_server() {
    wait_for_service "NX Server" \
        "curl --insecure -sk -f \"$LOCAL_SERVER_URL/api/ping\" > /dev/null 2>&1" \
        "$WAIT_TIMEOUT"
}

# -----------------------------------------------------------------------------
# restart_nx_media_server
#   Restarts the Nx media server service and waits for it to become available.
# -----------------------------------------------------------------------------
restart_nx_media_server() {
    echo "Restarting Nx Media Server..."
    systemctl restart networkoptix-metavms-mediaserver.service || {
        echo "Error: Failed to restart Nx Media Server."
        exit 1
    }
    wait_for_nx_server
}

###############################################################################
# Connectivity and Environment Check Functions
###############################################################################

# -----------------------------------------------------------------------------
# check_connectivity
#   Checks basic internet connectivity, DNS resolution, and access to NX_CLOUD_URL.
# -----------------------------------------------------------------------------
check_connectivity() {
    echo ""
    echo "=== Checking internet and DNS connectivity ==="

    # Basic check: ping Google's DNS to verify internet connectivity.
    echo "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        echo "Error: Unable to reach the internet. Check your network connection."
        exit 1
    fi
    echo "Internet connectivity OK."

    # DNS resolution check for the configured NX_CLOUD_HOST.
    echo "Checking DNS resolution for $NX_CLOUD_HOST..."
    if command -v dig &>/dev/null; then
        # Use 'dig' if available
        if ! dig +short "$NX_CLOUD_HOST" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' &>/dev/null; then
            echo "Error: DNS resolution failed."
            exit 1
        fi
    elif command -v nslookup &>/dev/null; then
        # Use 'nslookup' if 'dig' is not available
        if ! nslookup "$NX_CLOUD_HOST" &>/dev/null; then
            echo "Error: DNS resolution failed."
            exit 1
        fi
    else
        echo "Warning: Neither 'dig' nor 'nslookup' is installed; skipping explicit DNS test."
    fi
    echo "DNS resolution for $NX_CLOUD_HOST OK."

    # Test HTTP connectivity to the Nx cloud host.
    echo "Checking HTTP connectivity to $NX_CLOUD_URL..."
    if ! curl -sk --head --fail "$NX_CLOUD_URL" &>/dev/null; then
        echo "Error: Unable to connect to $NX_CLOUD_URL."
        exit 1
    fi
    echo "Connectivity to $NX_CLOUD_URL is OK."
}

# -----------------------------------------------------------------------------
# report_system_info
#   Gathers and logs information about the OS version, glibc version, etc.
# -----------------------------------------------------------------------------
report_system_info() {
    echo ""
    echo "=== Gathering system information ==="

    # OS version detection:
    if command -v lsb_release &>/dev/null; then
        echo "OS Version: $(lsb_release -ds)"
    elif [ -f /etc/os-release ]; then
        # If /etc/os-release is present, source it to get PRETTY_NAME.
        . /etc/os-release
        echo "OS Version: $PRETTY_NAME"
    else
        echo "Warning: Unable to determine OS version."
    fi

    # glibc version detection via 'ldd'
    if command -v ldd &>/dev/null; then
        local glibc_version
        glibc_version=$(ldd --version | head -n1 | awk '{print $NF}')
        echo "glibc Version: $glibc_version"
    else
        echo "Warning: 'ldd' not found; cannot determine glibc version."
    fi
}

###############################################################################
# Nx Server and Dependencies Installation
###############################################################################
# These functions download, install, and verify Nx server and other dependencies.

# -----------------------------------------------------------------------------
# install_libasound
#   Checks if libasound2 is available and installs it if not present.
# -----------------------------------------------------------------------------
install_libasound() {
    local package="libasound2"
    echo "Checking if '$package' is available in the repositories..."

    if apt-cache search "^$package$" | grep -q "^$package"; then
        echo "The package '$package' is available in the repositories."
        echo "Proceeding to check installation..."

        if dpkg -l | grep -q "^ii\s*$package"; then
            echo "The package '$package' is already installed."
        else
            echo "The package '$package' is not installed. Installing now..."
            apt-get -qq update && apt-get -qq install -y "$package" || {
                echo "Not able to install '$package'."
            }
        fi
    else
        echo "The package '$package' is not available in the current repositories."
    fi
}

# -----------------------------------------------------------------------------
# install_dep
#   Installs the primary dependencies needed by Nx and this script:
#   - libgomp1, gdebi, curl, jq, tar, cifs-utils, dnsutils, and libasound2
# -----------------------------------------------------------------------------
install_dep() {
    echo ""
    echo "=== Installing dependencies ==="
    apt-get -qq update || {
        echo "Error: apt-get update failed."
        exit 1
    }

    # Attempt to install libasound2 by calling our helper function
    install_libasound

    echo "Installing required packages."
    apt-get -qq install -y libgomp1 gdebi curl jq tar cifs-utils dnsutils || {
        echo "Info: Failed to install required packages."
        exit 1
    }
    echo "Dependencies installation completed."
}

# -----------------------------------------------------------------------------
# download_nx_server_package
#   Downloads the Nx Server .deb from the NX_SERVER_DOWNLOAD_URL.
# -----------------------------------------------------------------------------
download_nx_server_package() {
    echo "Downloading Nx server package from $NX_SERVER_DOWNLOAD_URL..."
    curl -fsSL -o ./nx_server_package.deb "$NX_SERVER_DOWNLOAD_URL" || {
        echo "Error: Failed to download Nx server package from $NX_SERVER_DOWNLOAD_URL"
        exit 1
    }
}

# -----------------------------------------------------------------------------
# install_nx_server_package
#   Installs the downloaded Nx server .deb package.
# -----------------------------------------------------------------------------
install_nx_server_package() {
    echo "Installing Nx server package..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get -qq install -y ./nx_server_package.deb; then
        echo "Error: Failed to install nx_server_package.deb" >&2
        exit 1
    fi
    echo "Nx server package installed successfully."
}

# -----------------------------------------------------------------------------
# install_nx
#   Coordinates the download and installation of the Nx server .deb package,
#   then waits for the Nx server to become available.
# -----------------------------------------------------------------------------
install_nx() {
    echo ""
    echo "=== Nx Server Installation ==="
    download_nx_server_package
    install_nx_server_package

    # Clean up the .deb after installation
    rm -f ./nx_server_package.deb

    # Wait for Nx Server to become responsive on the configured API endpoint
    wait_for_nx_server
}

###############################################################################
# Nx Authentication, Setup, and Registration
###############################################################################

# -----------------------------------------------------------------------------
# get_login_token
#   Attempts to authenticate against the Nx server using the original password,
#   then the new password if the original fails. Returns a valid token or exits.
# -----------------------------------------------------------------------------
get_login_token() {
    local session_data
    local token

    # First try the original password
    session_data=$(curl --insecure -sk -X POST "$LOCAL_SERVER_URL/rest/v3/login/sessions" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"$LOCAL_LOGIN\",\"password\":\"$LOCAL_PASSWORD\",\"setCookie\":true}") || {
        echo "Error: Failed to perform initial login request."
        exit 1
    }
    token=$(echo "$session_data" | jq -r '.token')

    # If token is null, it means the original password didn't work,
    # so try the new password.
    if [ "$token" == "null" ]; then
        session_data=$(curl --insecure -sk -X POST "$LOCAL_SERVER_URL/rest/v3/login/sessions" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{\"username\":\"$LOCAL_LOGIN\",\"password\":\"$LOCAL_PASSWORD_NEW\",\"setCookie\":true}") || {
            echo "Error: Failed to perform login request with new password."
            exit 1
        }
        token=$(echo "$session_data" | jq -r '.token')
    fi

    # If token is still null, authentication has failed.
    if [ "$token" == "null" ]; then
        echo "Error: Authentication with Nx server failed."
        exit 1
    fi
    
    # Echo the token so it can be captured in a calling function.
    echo "$token"
}

# -----------------------------------------------------------------------------
# logout_session
#   Logs out the specified session token from the Nx server.
# -----------------------------------------------------------------------------
logout_session() {
    local token="$1"
    curl --insecure -sk -X DELETE "$LOCAL_SERVER_URL/rest/v3/login/sessions/$token" >/dev/null 2>&1 || {
        echo "Warning: Failed to log out session with token $token."
    }
    curl --insecure -sk -X DELETE "$LOCAL_SERVER_URL/rest/v3/login/sessions" >/dev/null 2>&1 || {
        echo "Warning: Failed to delete all login sessions."
    }
}

# -----------------------------------------------------------------------------
# system_setup
#   Configures the Nx system with a new name and sets the local admin password
#   via Nx's /rest/v3/system/setup endpoint.
# -----------------------------------------------------------------------------
system_setup() {
    echo ""
    echo "=== Configuring Nx system ==="

    local token="$1"

    local setup_payload
    setup_payload="{\"name\":\"$NX_SYSTEM_NAME\",\"settingsPreset\":\"compatibility\",\"settings\":{},\"local\":{\"password\":\"$LOCAL_PASSWORD_NEW\",\"userAgent\":\"\"}}"

    local setup_response
    setup_response=$(curl --insecure -sk -X POST "$LOCAL_SERVER_URL/rest/v3/system/setup" \
        -H "accept: application/json" \
        -H "Content-Type: application/json" \
        -H "x-runtime-guid: $token" \
        -d "$setup_payload") || {
        echo "Error: Failed to execute system setup request."
        exit 1
    }

    local error_message
    error_message=$(echo "$setup_response" | jq -r '.errorString // empty')

    if [ -n "$error_message" ]; then
        # This often occurs if the system was already initialized.
        if [[ "$error_message" == *"Setup is only allowed for the new System"* ]]; then
            echo "Info: $error_message"
        else
            echo "Error: $error_message"
            exit 1
        fi
    else
        echo "System setup completed successfully."
    fi
}

# -----------------------------------------------------------------------------
# system_registration
#   Registers the Nx system using the provided license ID.
# -----------------------------------------------------------------------------
system_registration() {
    local token="$1"
    local license_id="$2"

    if [ -z "$license_id" ]; then
        echo "Error: License ID is required."
        exit 1
    fi

    echo ""
    echo "=== Registering Nx system with license ID: $license_id ==="

    local reg_payload='{
        "licenseBlock": ""
    }'

    local reg_response
    reg_response=$(curl --insecure -sk -X PUT "$LOCAL_SERVER_URL/rest/v3/licenses/$license_id?_strict=false" \
        -H "accept: application/json" \
        -H "Content-Type: application/json" \
        -H "x-runtime-guid: $token" \
        -d "$reg_payload") || {
        echo "Error: Failed to execute license registration request."
        exit 1
    }

    local error_message
    error_message=$(echo "$reg_response" | jq -r '.errorString // empty')

    # Check if the system is already registered or any other error has occurred.
    if [ -n "$error_message" ]; then
        if [[ "$error_message" == *"Reg is only allowed for unregistered System"* ]]; then
            echo "Info: $error_message"
        else
            echo "Error: $reg_response"
            echo "Token: $token"
            exit 1
        fi
    else
        echo "System registration completed successfully."
    fi
}

###############################################################################
# NxAI Plugin Installation and Configuration
###############################################################################

# -----------------------------------------------------------------------------
# install_plugin
#   Calls a remote install script for NxAI plugin, downloads NxAI Manager,
#   and restarts Nx Media Server.
# -----------------------------------------------------------------------------
install_plugin() {
    local token="$1"

    echo ""
    echo "=== Installing NxAI Plugin ==="

    # The remote install script is executed silently, with output suppressed.
    bash -c "$(curl -fsSL "$NX_AI_PLUGIN_INSTALL_URL")" package="$NX_AI_PLUGIN_VERSION" >/dev/null 2>&1 || {
        echo "Error: Failed to install NxAI plugin from $NX_AI_PLUGIN_INSTALL_URL"
        exit 1
    }

    echo "Downloading NxAI Manager plugin..."
    curl -fsSL -o ./nx_ai_plugin.tar.gz "$NX_AI_PLUGIN_DOWNLOAD_URL" || {
        echo "Error: Failed to download NxAI Manager plugin from $NX_AI_PLUGIN_DOWNLOAD_URL"
        exit 1
    }

    echo "Extracting NxAI Manager plugin..."
    tar -xf ./nx_ai_plugin.tar.gz \
        -C /opt/networkoptix-metavms/mediaserver/bin/plugins/nxai_plugin || {
        echo "Error: Failed to extract NxAI Manager plugin tarball."
        exit 1
    }
    rm -f ./nx_ai_plugin.tar.gz

    # Restart the Nx server to ensure it picks up the new plugin.
    restart_nx_media_server
}

###############################################################################
# Nx Cloud Connection
###############################################################################
# The functions below handle connecting the local Nx system to Nx Cloud.

# -----------------------------------------------------------------------------
# cloud_connect
#   Sends a request to Nx Cloud to create or retrieve a system "connect" token.
#   Returns an HTTP status code and response body in the format "<status>:<body>"
# -----------------------------------------------------------------------------
cloud_connect() {
    local token="$1"

    local cloud_credentials
    # Build a JSON object using jq -nc for a new system in Nx cloud
    cloud_credentials=$(jq -nc \
        --arg name "$NX_SYSTEM_NAME" \
        --arg email "$NX_CLOUD_USER" \
        --arg password "$NX_CLOUD_PASS" \
        '{"name":$name,"email":$email,"password":$password}')

    local curl_output
    curl_output=$(curl --insecure -sk -w "%{http_code}" -X POST "$NX_CLOUD_URL/api/systems/connect" \
        -H "Content-Type: application/json" \
        -d "$cloud_credentials" || true)

    # Extract the last 3 characters (HTTP code) and everything before that as body
    local len=${#curl_output}
    if (( len < 3 )); then
        echo "Error: Unexpectedly short response from cloud_connect: '$curl_output'"
        exit 1
    fi

    local status_code="${curl_output: -3}"
    local response_body="${curl_output::len-3}"

    echo "$status_code:$response_body"
}

# -----------------------------------------------------------------------------
# cloud_bind
#   Binds the local Nx system to the Nx Cloud system ID using the authKey/owner.
# -----------------------------------------------------------------------------
cloud_bind() {
    local token="$1"
    local system_id="$2"
    local auth_key="$3"
    local owner="$4"

    local bind_payload
    bind_payload=$(jq -nc \
        --arg systemId "$system_id" \
        --arg authKey "$auth_key" \
        --arg owner "$owner" \
        '{"systemId":$systemId,"authKey":$authKey,"owner":$owner}')

    local bind_response
    bind_response=$(curl --insecure -sk -w "%{http_code}" -X POST "$LOCAL_SERVER_URL/rest/v3/system/cloud/bind" \
        -H "Content-Type: application/json" \
        -H "x-runtime-guid: $token" \
        -d "$bind_payload" || true)

    local len=${#bind_response}
    if (( len < 3 )); then
        echo "Error: Unexpectedly short response from cloud_bind: '$bind_response'"
        exit 1
    fi

    local bind_status="${bind_response: -3}"
    local bind_body="${bind_response::len-3}"

    # Return a concatenation of JSON response plus the HTTP status code
    echo "${bind_body}${bind_status}"
}

# -----------------------------------------------------------------------------
# connect_to_cloud
#   Orchestrates the cloud connect and bind processes,
#   including handling various HTTP statuses.
# -----------------------------------------------------------------------------
connect_to_cloud() {
    echo ""
    echo "=== Connecting the Nx system to the cloud ==="

    local token="$1"

    local connect_response
    connect_response=$(cloud_connect "$token")

    # The format is <status_code>:<response_body>
    local status_code="${connect_response%%:*}"
    local response_body="${connect_response#*:}"

    # Validate that we have a 3-digit HTTP status code
    if [[ ! "$status_code" =~ ^[0-9]{3}$ ]]; then
        echo "Error: Could not parse a valid HTTP status code from '$connect_response'"
        exit 1
    fi

    if [ "$status_code" -eq 200 ]; then
        # Retrieve necessary fields from the response for binding
        local system_id
        system_id=$(echo "$response_body" | jq -r '.id')
        local auth_key
        auth_key=$(echo "$response_body" | jq -r '.authKey')
        local owner
        owner=$(echo "$response_body" | jq -r '.ownerAccountEmail')

        # Validate that all required fields were returned
        if [ -z "$system_id" ] || [ -z "$auth_key" ] || [ -z "$owner" ] ||
           [ "$system_id" == "null" ] || [ "$auth_key" == "null" ] || [ "$owner" == "null" ]; then
            echo "Error: Cloud connect response did not contain valid systemId/authKey/owner."
            exit 1
        fi

        local bind_response
        bind_response=$(cloud_bind "$token" "$system_id" "$auth_key" "$owner")

        local bind_status="${bind_response: -3}"
        local bind_body="${bind_response::${#bind_response}-3}"

        if [ "$bind_status" -eq 200 ]; then
            echo -e "\e[32mSuccessfully connected $NX_SYSTEM_NAME to the cloud as $NX_CLOUD_USER.\e[0m"
        else
            # Check if the system was already bound or if there's another error
            local error_string
            error_string=$(echo "$bind_body" | jq -r '.errorString // empty')

            if [[ "$error_string" == *"already bound"* ]]; then
                echo "Info: System $NX_SYSTEM_NAME is already bound to the cloud."
            else
                echo -e "\e[31mCould not bind $NX_SYSTEM_NAME to the cloud. Response: $bind_response.\e[0m"
            fi
        fi

    elif [ "$status_code" -eq 401 ]; then
        echo -e "\e[31mCloud authentication failed. Check username/password.\e[0m"
    else
        echo -e "\e[31mFailed to connect $NX_SYSTEM_NAME to the cloud. Status: $status_code, Response: $response_body\e[0m"
    fi
}

###############################################################################
# Test Camera Setup
###############################################################################

# -----------------------------------------------------------------------------
# install_testcamera
#   Creates a movie directory, downloads a sample MP4, and runs Nx testcamera.
# -----------------------------------------------------------------------------
install_testcamera() {
    echo ""
    echo "=== Setting up the test camera ==="

    echo "Creating movie directory: $MOVIE_DIR..."
    mkdir -p "$MOVIE_DIR" || {
        echo "Error: Failed to create movie directory."
        exit 1
    }
    chmod 775 "$MOVIE_DIR" || {
        echo "Error: Failed to set permissions on movie directory."
        exit 1
    }

    echo "Downloading sample movie from $MOVIE_URL..."
    curl -fsSL -o "$MOVIE_DIR/$MOVIE_FILE" "$MOVIE_URL" || {
        echo "Error: Failed to download sample movie from $MOVIE_URL"
        exit 1
    }

    chmod 775 "$MOVIE_DIR/$MOVIE_FILE" || {
        echo "Error: Failed to set permissions on the downloaded movie file."
        exit 1
    }

    echo "Starting test camera service..."
    # The testcamera process simulates a video stream from the downloaded MP4.
    nohup /opt/networkoptix-metavms/mediaserver/bin/testcamera --fps=24 -S "files=$MOVIE_DIR/$MOVIE_FILE" </dev/null >/dev/null 2>&1 &
    echo "Test camera started successfully."
}

# -----------------------------------------------------------------------------
# install_test_stream
#   Creates a movie directory, downloads a sample MP4, and runs Nx testcamera.
# -----------------------------------------------------------------------------
install_test_stream() {
    echo ""
    echo "=== Setting up the test stream ==="

    local token="$1"

    echo "Searching for $STREAM_URL"

    local dev_enable_payload="{
        \"credentials\": {
            \"user\": \"$STREAM_USER\",
            \"password\": \"$STREAM_PASS\"
        },
        \"mode\": \"addFoundDevices\",
        \"target\": {
            \"ip\": \"$STREAM_URL\"
        }
    }"

    local dev_enable_response
    dev_enable_response=$(curl --insecure -sk -X POST "$LOCAL_SERVER_URL/rest/v3/devices/*/searches" \
        -H "accept: application/json" \
        -H "Content-Type: application/json" \
        -H "x-runtime-guid: $token" \
        -d "$dev_enable_payload") || {
        echo "Error: Failed to enable stream."
        exit 1
    }

    local error_message
    error_message=$(echo "$dev_enable_response" | jq -r '.errorString // empty')

    if [ -n "$error_message" ]; then
        echo "Failed to enable stream."
    else
        echo "Stream enabled successfully."
    fi
}

###############################################################################
# OAAX Runtime Installation
###############################################################################
# This runtime is needed for Nx AI analytics to function properly.

# -----------------------------------------------------------------------------
# install_oaax_runtime
#   Downloads and extracts the runtime tar.gz for Nx AI analytics,
#   then restarts Nx Media Server.
# -----------------------------------------------------------------------------
install_oaax_runtime() {
    local token="$1"

    echo ""
    echo "=== Installing OAAX runtime ==="

    echo "Downloading OAAX runtime from $NX_AI_OAAX_RUNTIME_DOWNLOAD_URL..."
    curl -fsSL -o ./runtime.tar.gz "$NX_AI_OAAX_RUNTIME_DOWNLOAD_URL" || {
        echo "Error: Failed to download OAAX runtime from $NX_AI_OAAX_RUNTIME_DOWNLOAD_URL"
        exit 1
    }

    echo "Extracting OAAX runtime..."
    tar -xf ./runtime.tar.gz \
        -C /opt/networkoptix-metavms/mediaserver/bin/plugins/nxai_plugin/nxai_manager/bin || {
        echo "Error: Failed to extract OAAX runtime."
        exit 1
    }

    # Write a simple identifier file for this runtime
    echo "Nx CPU" | tee /opt/networkoptix-metavms/mediaserver/bin/plugins/nxai_plugin/nxai_manager/bin/installed_runtime.txt >/dev/null || {
        echo "Error: Failed to write runtime identifier file."
        exit 1
    }

    rm -f ./runtime.tar.gz

    restart_nx_media_server
}

###############################################################################
# Enable/Disable NxAI Plugin on Detected Devices
###############################################################################

# -----------------------------------------------------------------------------
# enable_device_recording
#   Enables basic continuous recording on a given device.
# -----------------------------------------------------------------------------
enable_device_recording() {
    local token="$1"
    local device_id="$2"

    if [ -z "$device_id" ]; then
        echo "Error: Device ID is required."
        exit 1
    fi

    echo "Enabling basic recording for device: $device_id"

    # Minimal schedule that always records at the lowest stream quality
    local dev_enable_payload='{
        "parameters": {},
        "schedule": {
            "isEnabled": true,
            "tasks": [
                {
                    "dayOfWeek": 1,
                    "startTime": 0,
                    "endTime": 86400,
                    "recordingType": "always",
                    "streamQuality": "low",
                    "fps": 15,
                    "bitrateKbps": 0,
                    "metadataTypes": "none"
                },
                {
                    "dayOfWeek": 2,
                    "startTime": 0,
                    "endTime": 86400,
                    "recordingType": "always",
                    "streamQuality": "low",
                    "fps": 15,
                    "bitrateKbps": 0,
                    "metadataTypes": "none"
                },
                {
                    "dayOfWeek": 3,
                    "startTime": 0,
                    "endTime": 86400,
                    "recordingType": "always",
                    "streamQuality": "low",
                    "fps": 15,
                    "bitrateKbps": 0,
                    "metadataTypes": "none"
                },
                {
                    "dayOfWeek": 4,
                    "startTime": 0,
                    "endTime": 86400,
                    "recordingType": "always",
                    "streamQuality": "low",
                    "fps": 15,
                    "bitrateKbps": 0,
                    "metadataTypes": "none"
                },
                {
                    "dayOfWeek": 5,
                    "startTime": 0,
                    "endTime": 86400,
                    "recordingType": "always",
                    "streamQuality": "low",
                    "fps": 15,
                    "bitrateKbps": 0,
                    "metadataTypes": "none"
                },
                {
                    "dayOfWeek": 6,
                    "startTime": 0,
                    "endTime": 86400,
                    "recordingType": "always",
                    "streamQuality": "low",
                    "fps": 15,
                    "bitrateKbps": 0,
                    "metadataTypes": "none"
                },
                {
                    "dayOfWeek": 7,
                    "startTime": 0,
                    "endTime": 86400,
                    "recordingType": "always",
                    "streamQuality": "low",
                    "fps": 15,
                    "bitrateKbps": 0,
                    "metadataTypes": "none"
                }
            ]
        }
    }'

    local dev_enable_response
    dev_enable_response=$(curl --insecure -sk -X PATCH "$LOCAL_SERVER_URL/rest/v3/devices/$device_id?_strict=false" \
        -H "accept: application/json" \
        -H "Content-Type: application/json" \
        -H "x-runtime-guid: $token" \
        -d "$dev_enable_payload") || {
        echo "Error: Failed to enable device recording."
        exit 1
    }

    local error_message
    error_message=$(echo "$dev_enable_response" | jq -r '.errorString // empty')

    if [ -n "$error_message" ]; then
        if [[ "$error_message" == *"Reg is only allowed for unregistered System"* ]]; then
            echo "Info: $error_message"
        else
            echo "Error: $error_message"
            exit 1
        fi
    else
        echo "Device recording enabled successfully."
    fi
}

# -----------------------------------------------------------------------------
# enable_plugin
#   Retrieves the Nx AI Manager plugin ID, waits for devices to appear,
#   and either enables or disables the NxAI plugin on those devices
#   based on ENABLE_AI_PLUGIN.
# -----------------------------------------------------------------------------
enable_plugin() {
    local token="$1"

    echo ""
    echo "=== Adjusting NxAI Plugin availability on devices ==="

    local base_url="$LOCAL_SERVER_URL/rest/v3"

    echo "Retrieving Nx AI Manager plugin ID..."
    local plugin_response
    plugin_response=$(curl -sk -H "Authorization: Bearer $token" "$base_url/analytics/engines") || {
        echo "Error: Failed to retrieve analytics engines."
        exit 1
    }

    local plugin_id
    plugin_id=$(echo "$plugin_response" | jq -r '.[] | select(.name == "NX AI Manager") | .id')

    # If no plugin ID is found, we cannot proceed with enabling/disabling it
    if [ -z "$plugin_id" ] || [ "$plugin_id" == "null" ]; then
        echo "Error: 'NX AI Manager' plugin not found."
        exit 1
    fi

    echo "Waiting for devices to appear..."
    local devices_response="[]"
    local attempt_count=0

    # Wait until we find at least one device or exceed MAX_PLUGIN_ATTEMPTS
    while [[ "$devices_response" == "[]" && $attempt_count -lt $MAX_PLUGIN_ATTEMPTS ]]; do
        sleep 3
        devices_response=$(curl -sk -H "Authorization: Bearer $token" "$base_url/devices") || {
            echo "Error: Failed to retrieve devices."
            exit 1
        }
        (( attempt_count++ ))
    done

    if [[ "$devices_response" == "[]" ]]; then
        echo "Error: No devices found after waiting."
        exit 1
    fi

    echo "Configuring NxAI plugin for discovered devices..."
    # Iterate over each device in the devices_response JSON.
    echo "$devices_response" | jq -c '.[]' | while read -r device_data; do
        local device_id
        device_id=$(echo "$device_data" | jq -r '.id')

        if [ -z "$device_id" ] || [ "$device_id" == "null" ]; then
            echo "Warning: Skipping a device with no valid ID."
            continue
        fi

        # Depending on ENABLE_AI_PLUGIN, either add or remove the plugin ID
        local patch_data
        if [ "$ENABLE_AI_PLUGIN" == "false" ]; then
            patch_data=$(echo "$device_data" | jq --arg plugin_id "$plugin_id" \
                '.userEnabledAnalyticsEngineIds -= [$plugin_id]')
        else
            patch_data=$(echo "$device_data" | jq --arg plugin_id "$plugin_id" \
                '.userEnabledAnalyticsEngineIds += [$plugin_id] |
                 .parameters.nxAI.PluginSettings.deviceActiveSwitch = "true"')
        fi

        local response
        response=$(curl -sk -X PATCH \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$patch_data" \
            "$base_url/devices/$device_id") || {
            echo "Error: Failed to patch device $device_id."
            continue
        }

        local status
        status=$(echo "$response" | jq -r '.status')

        if [ -z "$status" ] || [ "$status" == "null" ]; then
            echo "Warning: No status returned for device $device_id. Response: $response"
        else
            echo "Configuration status for device $device_id: $status"
            # If ENABLE_DEVICE_RECORDING is true, enable continuous recording.
            if [ "$ENABLE_DEVICE_RECORDING" == "true" ]; then
                enable_device_recording "$token" "$device_id"
            fi
        fi
    done
}

###############################################################################
# Functions for Merging Systems
###############################################################################
# The functions below handle merging multiple Nx Cloud systems
# if they share the same name.

# -----------------------------------------------------------------------------
# check_status
#   Verifies the HTTP status code from a response is acceptable (200 or 307).
#   Otherwise, logs an error and exits.
# -----------------------------------------------------------------------------
check_status() {
    local code="$1"
    local body="$2"
    if [[ "$code" == "200" || "$code" == "307" ]]; then
        return 0
    else
        echo "Error: HTTP $code"
        echo "$body"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# request_api
#   A wrapper around curl to handle Nx Cloud API calls that may need
#   to follow redirects (HTTP 307). Returns the JSON response body.
# -----------------------------------------------------------------------------
request_api() {
    local base_url="$1"
    local uri="$2"
    local method="$3"
    shift 3

    local response
    response=$(curl -s -S -k -X "$method" \
        -H "Content-Type: application/json" \
        -w "HTTPSTATUS:%{http_code}" \
        -o - \
        -k "$@" "${base_url}${uri}")

    local body
    body="${response%HTTPSTATUS:*}"
    local code
    code="${response##*HTTPSTATUS:}"

    # If the code is 307, we fetch the redirect location and try again.
    if [[ "$code" == "307" ]]; then
        local redirect_url
        redirect_url=$(curl -s -k -I -X "$method" -H "Content-Type: application/json" -k "$@" "${base_url}${uri}" \
            | grep -i "^Location:" | awk '{print $2}' | tr -d '\r')
        response=$(curl -s -S -k -X "$method" \
            -H "Content-Type: application/json" \
            -w "HTTPSTATUS:%{http_code}" \
            -o - \
            -k "$@" "$redirect_url")
        body="${response%HTTPSTATUS:*}"
        code="${response##*HTTPSTATUS:}"
    fi

    check_status "$code" "$body"
    echo "$body"
}

# -----------------------------------------------------------------------------
# create_cloud_auth_payload
#   Creates the JSON payload required for OAuth2 token retrieval
#   to manage Nx Cloud systems.
# -----------------------------------------------------------------------------
create_cloud_auth_payload() {
    jq -n --arg u "$1" --arg p "$2" '{
        grant_type: "password",
        response_type: "token",
        client_id: "3rdParty",
        username: $u,
        password: $p
    }'
}

# -----------------------------------------------------------------------------
# get_token
#   Extracts the 'access_token' field from a JSON response via jq.
# -----------------------------------------------------------------------------
get_token() {
    jq -r '.access_token // empty'
}

# -----------------------------------------------------------------------------
# is_expired_cloud
#   Checks if the token's 'expires_in' is too low, indicating it's nearly expired.
# -----------------------------------------------------------------------------
is_expired_cloud() {
    local expires_in
    expires_in=$(echo "$1" | jq -r '.expires_in // 999999')
    (( expires_in < RESPONSE_EXPIRATION_TIMEOUT_S ))
}

# -----------------------------------------------------------------------------
# merge_systems
#   Given a master and a slave system ID, retrieves tokens for both
#   and merges the slave into the master if possible.
# -----------------------------------------------------------------------------
merge_systems() {
    local master_id="$1"
    local slave_id="$2"
    local auth_header="$3"

    # Prepare OAuth payloads for the master system
    local master_oauth_payload
    master_oauth_payload=$(jq -n --arg u "$NX_CLOUD_USER" --arg p "$NX_CLOUD_PASS" --arg s "$master_id" '{
        grant_type: "password",
        response_type: "token",
        client_id: "3rdParty",
        username: $u,
        password: $p,
        scope: ("cloudSystemId=" + $s)
    }')

    # Prepare OAuth payloads for the slave system
    local slave_oauth_payload
    slave_oauth_payload=$(jq -n --arg u "$NX_CLOUD_USER" --arg p "$NX_CLOUD_PASS" --arg s "$slave_id" '{
        grant_type: "password",
        response_type: "token",
        client_id: "3rdParty",
        username: $u,
        password: $p,
        scope: ("cloudSystemId=" + $s)
    }')

    # Request master and slave tokens from Nx Cloud
    local master_response
    master_response=$(request_api "$NX_CLOUD_URL" "/cdb/oauth2/token" "POST" -d "$master_oauth_payload")

    local slave_response
    slave_response=$(request_api "$NX_CLOUD_URL" "/cdb/oauth2/token" "POST" -d "$slave_oauth_payload")

    # Parse out the tokens
    local master_token
    master_token=$(echo "$master_response" | get_token)
    local slave_token
    slave_token=$(echo "$slave_response" | get_token)

    # If tokens cannot be retrieved, skip merging.
    if [[ -z "$master_token" || -z "$slave_token" ]]; then
        echo "Warning: Failed to retrieve system tokens for master=$master_id or slave=$slave_id"
        echo "Skipping merge for these systems."
        return
    fi

    echo "Master ($master_id) and Slave ($slave_id) tokens retrieved successfully."

    # Build the request body for merging
    local merge_body_json
    merge_body_json=$(jq -n --arg master "$master_token" --arg slave "$slave_token" --arg slaveid "$slave_id" '{
        masterSystemAccessToken: $master,
        slaveSystemAccessToken:  $slave,
        systemId:               $slaveid
    }')

    local merge_url
    merge_url="/cdb/systems/$master_id/merged_systems/"
    local response
    response=$(request_api "$NX_CLOUD_URL" "$merge_url" "POST" \
        -H "$auth_header" \
        -H 'accept: application/json' \
        -d "$merge_body_json")

    echo "Merge completed for $slave_id -> $master_id."
}

# -----------------------------------------------------------------------------
# process_systems
#   Determines if multiple Nx Cloud systems share the same name and merges them.
# -----------------------------------------------------------------------------
process_systems() {
    local systems_response="$1"
    local auth_header="$2"

    # Gather all system IDs whose 'name' matches NX_SYSTEM_NAME
    mapfile -t system_ids < <(echo "$systems_response" | \
        jq -r ".systems[] | select(.name == \"${NX_SYSTEM_NAME}\") | .id")

    local count=${#system_ids[@]}
    if (( count == 0 )); then
        echo "No systems found with the name ${NX_SYSTEM_NAME}."
        return
    elif (( count == 1 )); then
        echo "Only one system found (${system_ids[0]}). Nothing to merge."
        return
    else
        echo "Multiple systems found for '${NX_SYSTEM_NAME}':"
        printf '  %s\n' "${system_ids[@]}"

        local master_id="${system_ids[0]}"
        for ((i=1; i<count; i++)); do
            local slave_id="${system_ids[$i]}"
            echo "Merging Slave ($slave_id) into Master ($master_id)..."
            merge_systems "$master_id" "$slave_id" "$auth_header"
        done
    fi
}

# -----------------------------------------------------------------------------
# do_merge
#   Logs into Nx Cloud, finds multiple systems matching NX_SYSTEM_NAME,
#   and merges them into a single system if ENABLE_SAME_NAME_SYSTEM_MERGE is true.
# -----------------------------------------------------------------------------
do_merge() {
    echo ""
    echo "=== Merging systems with the same name ==="

    local oauth_payload
    oauth_payload=$(create_cloud_auth_payload "$NX_CLOUD_USER" "$NX_CLOUD_PASS")

    local oauth_response
    oauth_response=$(request_api "$NX_CLOUD_URL" "/cdb/oauth2/token" "POST" -d "$oauth_payload")

    # Check if the token is valid or near expiration.
    if is_expired_cloud "$oauth_response"; then
        echo "Warning: Token is about to expire or invalid; cannot proceed with merges."
        return
    fi

    local cloud_token
    cloud_token=$(echo "$oauth_response" | get_token)
    if [[ -z "$cloud_token" ]]; then
        echo "Warning: Failed to retrieve cloud token; cannot proceed with merges."
        return
    fi
    echo "Cloud token retrieved successfully."

    local cloud_auth_header="Authorization: Bearer $cloud_token"

    echo "Fetching activated systems from Nx Cloud..."
    local systems_response
    systems_response=$(request_api "$NX_CLOUD_URL" "/cdb/systems?systemStatus=activated" \
        "GET" -H "$cloud_auth_header")

    echo "Systems retrieved successfully."
    process_systems "$systems_response" "$cloud_auth_header"

    echo "Cleaning up token..."
    local clean_response
    clean_response=$(request_api "$NX_CLOUD_URL" "/cdb/oauth2/token/${cloud_token}" \
        "DELETE" -H "$cloud_auth_header")

    local result_code
    result_code=$(echo "$clean_response" | jq -r '.resultCode // empty')

    if [[ "$result_code" == "ok" ]]; then
        echo "Token cleaned up successfully."
    else
        echo "Warning: Token cleanup returned: $clean_response"
    fi
}

###############################################################################
# Main
###############################################################################
# This is the primary entry point. It calls each of the above-defined functions
# in a logical sequence to install Nx, configure the system, install plugins,
# connect to the cloud, and optionally merge Nx Cloud systems.

main() {
    # 1) Install dependencies
    install_dep

    # 2) Check connectivity
    check_connectivity

    # 3) Report system info
    report_system_info

    # 4) Nx Server installation
    install_nx

    # Obtain Nx session token once, (re)use it
    local nx_token
    nx_token=$(get_login_token)

    # 5) Nx System setup and registration
    system_setup "$nx_token"
    logout_session "$nx_token"

    nx_token=$(get_login_token)
    system_registration "$nx_token" "$SYSTEM_LICENSE_KEY"
    logout_session "$nx_token"

    # 6) Install NXAI plugin
    nx_token=$(get_login_token)
    install_plugin "$nx_token"
    logout_session "$nx_token"

    # 7) Connect System to NX Cloud
    nx_token=$(get_login_token)
    connect_to_cloud "$nx_token"
    logout_session "$nx_token"

    # 8) Install and run a test camera
    if [ "$ENABLE_TESTCAMERA" == "true" ]; then
        install_testcamera
    fi

    # 9) Install and enable a test stream
    if [ "$ENABLE_TEST_STREAM" == "true" ]; then
        nx_token=$(get_login_token)
        install_test_stream "$nx_token"
        logout_session "$nx_token"
    fi

    # 10) Install the OAAX runtime
    nx_token=$(get_login_token)
    install_oaax_runtime "$nx_token"
    logout_session "$nx_token"

    # 11) Enable plugin on devices
    nx_token=$(get_login_token)
    enable_plugin "$nx_token"
    logout_session "$nx_token"

    # 12) Merge systems if so configured
    if [ "$ENABLE_SAME_NAME_SYSTEM_MERGE" == "true" ]; then
        do_merge
    fi

}

# Start the script execution by calling main().
main
