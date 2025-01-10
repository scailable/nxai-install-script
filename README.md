# Network Optix AI Plugin Installer Script

## Introduction

The **NxAI Installer** script automates the installation and configuration of the [Network Optix AI Manager Plugin](https://nx.docs.scailable.net/) for Network Optix Meta. It streamlines the setup process by handling dependencies, server installation, authentication, plugin setup, cloud connection, and system merging. This ensures a seamless and efficient deployment of the NxAI environment.

## What does the script do? 

After setting the necessary environment variables and running the installer, the script will perform the following actions:

1. **Install Dependencies**: Updates package lists and installs required packages.
2. **Check Connectivity**: Verifies internet access, DNS resolution, and connectivity to Nx Cloud.
3. **Report System Info**: Logs information about the operating system and `glibc` version.
4. **Install Nx Server**: Downloads and installs the Nx Server package.
5. **Authenticate and Register**: Sets up the Nx system and registers it with a license.
6. **Install Plugins**: Installs the Nx AI plugin and OAAX runtime.
7. **Connect to Nx Cloud**: Links the local system to Nx Cloud and merges systems with the same name.
8. **Optional Components**: Installs a test camera and/or test stream if enabled.
9. **Autorun AI**: Starts recording on devices, enables AI default model, and generates bounding boxes.

## Prerequisites

Before running the installer, ensure that your system meets the following requirements:

- **Operating System**: Debian-based Linux distribution (e.g., Ubuntu).
- **Root Privileges**: The script must be executed with root privileges.
- **Internet Connectivity**: Required for downloading packages and connecting to Nx Cloud.

## TL;DR

```bash
export NX_CLOUD_USER="your_email@example.com"
export NX_CLOUD_PASS="your_secure_password"
export NX_SYSTEM_NAME="MyNxSystem"
export LOCAL_PASSWORD_NEW="new_secure_password"
sudo -E bash run_nxai_installer.sh
```

Or, if you want to easily modify the above and other variables:

```bash
# Step 1: Set environment variables by editing set_nxai_installer.sh and run:
source set_nxai_installer.sh

# Step 2: Install and configure NxAI by running:
sudo -E bash run_nxai_installer.sh

# --OR-- To run both steps in a single command:
source set_nxai_installer.sh && sudo -E bash run_nxai_installer.sh
```

## Features of the script

- **Automated Installation**: Installs necessary dependencies and the Network Optix server.
- **System Configuration**: Authenticates, sets up the Nx system, and registers a license.
- **Plugin Management**: Installs the Nx AI plugin and OAAX runtime.
- **Recording Setup**: Enables minimal recording on all connected devices.
- **Cloud Integration**: Connects the local Nx system to Nx Cloud and merges multiple systems with the same name.
- **Optional Components**: Supports the installation of test cameras and streams for verification.

## Environment Variables

The installer relies on several environment variables to configure the installation and setup process. These variables are categorized into **required** and **optional**. Below is a comprehensive list along with their descriptions and default values (if applicable):

### Required Environment Variables

| Variable             | Description                                                | Example                  |
| -------------------- | ---------------------------------------------------------- | ------------------------ |
| `NX_CLOUD_USER`      | Nx Cloud username/email.                                   | `your_email@example.com` |
| `NX_CLOUD_PASS`      | Nx Cloud password (minimum 8 characters).                  | `your_secure_password`   |
| `NX_SYSTEM_NAME`     | Desired name for your Nx system.                           | `MyNxSystem`             |
| `LOCAL_PASSWORD_NEW` | New password for the local Nx admin account (min 8 chars). | `new_secure_password`    |

### Optional Environment Variables

| Variable                          | Description                                           | Default Value                                                |
| --------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------ |
| `SYSTEM_LICENSE_KEY`              | System license key.                                   | `"0000-0000-0000-0029"`                                      |
| `ENABLE_AI_PLUGIN`                | Enable Nx AI Plugin.                                  | `true`                                                       |
| `ENABLE_SAME_NAME_SYSTEM_MERGE`   | Allow merging systems with the same name in Nx Cloud. | `true`                                                       |
| `ENABLE_DEVICE_RECORDING`         | Enable minimal recording on all devices.              | `true`                                                       |
| `ENABLE_TESTCAMERA`               | Enable installation of a test camera.                 | `false` (set to `true` to enable)                            |
| `ENABLE_TEST_STREAM`              | Enable installation of a test stream.                 | `true` (set to `false` to disable)                           |
| `NX_CLOUD_HOST`                   | Nx Cloud host.                                        | `"meta.nxvms.com"`                                           |
| `NX_CLOUD_URL`                    | Nx Cloud URL.                                         | `"https://${NX_CLOUD_HOST}"`                                 |
| `LOCAL_LOGIN`                     | Local Nx admin username.                              | `"admin"`                                                    |
| `LOCAL_PASSWORD`                  | Original local Nx admin password.                     | `"admin"`                                                    |
| `LOCAL_SERVER_URL`                | Local Nx server URL.                                  | `"https://localhost:7001"`                                   |
| `NX_SERVER_DOWNLOAD_URL`          | URL to download the Nx Server package.                | `"https://updates.networkoptix.com/metavms/...`              |
| `NX_AI_PLUGIN_VERSION`            | Version of the Nx AI Plugin to install.               | `"nightly"`                                                  |
| `NX_AI_PLUGIN_INSTALL_URL`        | URL to install the Nx AI Plugin.                      | `"https://artifactory.nxvms.dev/.../install.sh"`             |
| `NX_AI_PLUGIN_DOWNLOAD_URL`       | URL to download the Nx AI Manager plugin.             | `"https://artifactory.nxvms.dev/.../nxai_manager-x86_64.tgz"` |
| `NX_AI_OAAX_RUNTIME_DOWNLOAD_URL` | URL to download the OAAX runtime for Nx AI analytics. | `"https://artifactory.nxvms.dev/.../cpu-x86_64-ort.tar.gz"`  |
| `MOVIE_DIR`                       | Directory to store test camera footage.               | `"/opt/movies"`                                              |
| `MOVIE_URL`                       | URL of the test movie to download.                    | `"http://www.robinvanemden.dds.nl/walking.mp4"`              |
| `MOVIE_FILE`                      | Filename extracted from `MOVIE_URL`.                  | `basename of MOVIE_URL`                                      |
| `STREAM_URL`                      | Stream URL for the test stream.                       | `"rtsp://5.75.171.116:8554/face-blur-4-people"`              |
| `STREAM_USER`                     | Username for the stream (if required).                | `""`                                                         |
| `STREAM_PASS`                     | Password for the stream (if required).                | `""`                                                         |
| `MAX_PLUGIN_ATTEMPTS`             | Maximum attempts to wait for a plugin.                | `10`                                                         |
| `WAIT_TIMEOUT`                    | Timeout for operations in seconds.                    | `60`                                                         |
| `RESPONSE_EXPIRATION_TIMEOUT_S`   | Expiration timeout for responses in seconds.          | `10`                                                         |
