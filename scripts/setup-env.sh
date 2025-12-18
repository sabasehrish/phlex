#!/bin/bash

# Phlex Environment Setup Script
# This script configures the environment for building the Phlex project
# It supports multiple deployment scenarios:
#   - Multi-project workspace with Spack MPD
#   - Standalone repository with Spack
#   - Standalone repository with system packages
#   - CI/container environments
#
# NOTE: This script should be SOURCED, not executed directly
# Usage: source scripts/setup-env.sh
#        . scripts/setup-env.sh

# Colors for output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Output functions
log() {
    echo -e "${BLUE}[Phlex Setup]${NC} $1"
}

success() {
    echo -e "${GREEN}[Phlex Setup]${NC} $1"
}

error() {
    echo -e "${RED}[Phlex Setup]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[Phlex Setup]${NC} $1"
}

# Function to handle errors and return instead of exit
handle_error() {
    local line_no=$1
    local error_code=$2
    error "Error on line $line_no: Command exited with status $error_code"
    error "Failed to set up Phlex environment"
    trap - ERR
    return $error_code
}

# Ensure script is sourced, not executed
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced - set up error trap
    trap 'handle_error ${LINENO} $?' ERR
else
    # Script is being executed directly
    echo "Error: This script should be sourced, not executed directly" >&2
    echo "Usage: source scripts/setup-env.sh" >&2
    echo "       . scripts/setup-env.sh" >&2
    exit 1
fi

log "Setting up Phlex build environment..."

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_SOURCE="$(dirname "$SCRIPT_DIR")"

# Detect workspace structure and build mode
detect_build_mode() {
    # Check if we're in a multi-project structure
    # Indicators: parent directory has 'srcs' subdirectory containing our project
    local potential_workspace="$(dirname "$(dirname "$PROJECT_SOURCE")")"

    if [[ -d "$potential_workspace/srcs" && -d "$potential_workspace/srcs/phlex" ]]; then
        # Multi-project mode
        BUILD_MODE="multi-project"
        WORKSPACE_ROOT="$potential_workspace"
        SOURCE_ROOT="$WORKSPACE_ROOT/srcs"
        PHLEX_SOURCE_DIR="$SOURCE_ROOT/phlex"
        PHLEX_BUILD_DIR="${PHLEX_BUILD_DIR:-$WORKSPACE_ROOT/build}"
        log "Detected multi-project workspace structure"
    else
        # Standalone mode
        BUILD_MODE="standalone"
        WORKSPACE_ROOT="$(dirname "$PROJECT_SOURCE")"
        SOURCE_ROOT="$PROJECT_SOURCE"
        PHLEX_SOURCE_DIR="$PROJECT_SOURCE"
        PHLEX_BUILD_DIR="${PHLEX_BUILD_DIR:-$WORKSPACE_ROOT/build}"
        log "Detected standalone repository structure"
    fi

    export BUILD_MODE
    export WORKSPACE_ROOT
    export SOURCE_ROOT
    export PHLEX_SOURCE_DIR
    export PHLEX_BUILD_DIR
}

# Detect CI/container environment
detect_ci_environment() {
    if [[ -n "${CI}" || -n "${GITHUB_ACTIONS}" ]]; then
        log "Detected CI environment"
        return 0
    fi

    # Check for container-specific Spack setup
    if [[ -f "/spack/share/spack/setup-env.sh" ]]; then
        log "Detected container environment with Spack at /spack"
        return 0
    fi

    return 1
}

# Setup Spack environment (optional - gracefully degrades)
setup_spack_environment() {
    # If SPACK_ROOT already set, Spack is already configured
    if [[ -n "${SPACK_ROOT}" ]]; then
        log "Spack already configured (SPACK_ROOT=${SPACK_ROOT})"
        return 0
    fi

    # Try to find and source Spack setup script
    local spack_setup_paths=(
        "/spack/share/spack/setup-env.sh"                              # Container
        "${PHLEX_SPACK_ENV}/../../share/spack/setup-env.sh"            # Custom env
        "${HOME}/spack/share/spack/setup-env.sh"                       # User install
        "/usr/local/spack/share/spack/setup-env.sh"                    # System install
        "/opt/spack/share/spack/setup-env.sh"                          # Alt system
        "/cvmfs/fermilab.opensciencegrid.org/products/spack/current/share/spack/setup-env.sh"  # FNAL OSG
    )

    # Add user-specified path if provided
    if [[ -n "${SPACK_ROOT}" ]]; then
        # Spack already configured, re-source to ensure functions are loaded
        if [[ -f "${SPACK_ROOT}/share/spack/setup-env.sh" ]]; then
            spack_setup_paths=("${SPACK_ROOT}/share/spack/setup-env.sh" "${spack_setup_paths[@]}")
        fi
    elif [[ -n "${PHLEX_SPACK_ROOT}" ]]; then
        spack_setup_paths=("${PHLEX_SPACK_ROOT}/share/spack/setup-env.sh" "${spack_setup_paths[@]}")
    fi

    for setup_path in "${spack_setup_paths[@]}"; do
        if [[ -f "$setup_path" ]]; then
            log "Loading Spack from: $setup_path"
            . "$setup_path" || {
                warn "Failed to source Spack setup script"
                return 1
            }
            return 0
        fi
    done

    # Spack not found - this is OK, user may use system packages
    warn "Spack not found - assuming dependencies from system or other package manager"
    warn "If you want to use Spack, set PHLEX_SPACK_ROOT to your Spack installation"
    warn "Example: export PHLEX_SPACK_ROOT=/path/to/spack"
    return 1
}

# Activate the Phlex Spack environment
activate_phlex_spack_environment() {
    # Only proceed if Spack is available
    if ! command -v spack &> /dev/null; then
        error "Spack command not found. 'setup_spack_environment' should have handled this."
        return 1
    fi

    # Define the local spack environment path and source yaml
    local local_env_path="${WORKSPACE_ROOT}/.phlex-spack-env"
    local spack_yaml_path="${PHLEX_SOURCE_DIR}/ci/spack.yaml"

    # Check if the environment is already active
    if [[ -n "${SPACK_ENV:-}" && "$(readlink -f "$SPACK_ENV")" == "$(readlink -f "$local_env_path")" ]]; then
        log "Phlex Spack environment already active: $SPACK_ENV"
        return 0
    fi

    # If the environment doesn't exist, create it from the CI configuration
    if [[ ! -f "$local_env_path/spack.yaml" ]]; then
        log "Local Phlex Spack environment not found. Creating it at: $local_env_path"
        log "This will use the configuration from ${spack_yaml_path}"
        spack env create -d "$local_env_path" "$spack_yaml_path" || {
            error "Failed to create Spack environment from ${spack_yaml_path}"
            return 1
        }
        log "Spack environment created. Concretizing packages..."
        spack -e "$local_env_path" concretize || {
            error "Failed to concretize Spack environment."
            return 1
        }
        success "Spack environment created successfully."
        warn "Dependencies are not yet installed. Run 'spack -e ${local_env_path} install' to install them."
        warn "This may take a significant amount of time."
    fi

    # Activate the environment
    log "Activating Phlex Spack environment: ${local_env_path}"
    if ! spack env activate "$local_env_path"; then
        error "Failed to activate Spack environment at '${local_env_path}'"
        return 1
    fi

    success "Phlex Spack environment activated."
    log "All required tools (compilers, CMake, etc.) are now available from Spack."
    return 0
}


# Check for required build tools (DEPRECATED - Spack handles this now)
check_build_tools() {
    if ! command -v spack &> /dev/null; then
      error "Spack is required but not found in the environment."
      return 1
    fi
    log "Build tool check is handled by the Spack environment."
    return 0
}

# Main setup flow
main_setup() {
    # Detect build mode and set paths
    detect_build_mode

    # Ensure build directory exists
    if ! mkdir -p "${PHLEX_BUILD_DIR}" 2>/dev/null; then
        warn "Failed to create build directory: ${PHLEX_BUILD_DIR}"
        warn "Please check permissions and disk space"
    fi

    # Try to setup Spack (optional - will warn if not found)
    setup_spack_environment

    # Try to activate Spack environment (optional)
    activate_phlex_spack_environment

    # Set CMake-specific variables for consistent builds
    export CMAKE_EXPORT_COMPILE_COMMANDS=ON
    export CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-RelWithDebInfo}"

    # Check for required tools (fails if critical tools missing)
    if ! check_build_tools; then
        error "Environment setup incomplete - missing critical build tools"
        trap - ERR
        return 1
    fi

    # Print environment summary
    echo ""
    success "Environment setup complete!"
    log "Build mode: ${BUILD_MODE}"
    log "Workspace root: ${WORKSPACE_ROOT}"
    log "Source directory: ${PHLEX_SOURCE_DIR}"
    log "Build directory: ${PHLEX_BUILD_DIR}"
    if [[ -n "${CMAKE_PREFIX_PATH}" ]]; then
        log "CMAKE_PREFIX_PATH: ${CMAKE_PREFIX_PATH}"
    fi
    if command -v spack &> /dev/null; then
        local spack_env_status
        spack_env_status="$(spack env status 2>/dev/null || echo "No active environment")"
        log "Spack: available (${spack_env_status})"
    else
        log "Spack: not available (using system packages)"
    fi
    echo ""

    # Provide helpful next steps if in interactive mode
    if [[ $- == *i* ]]; then
        log "To configure and build the project:"
        if [[ -f "${PHLEX_SOURCE_DIR}/CMakePresets.json" ]]; then
            log "  cmake --preset default -S ${SOURCE_ROOT} -B ${PHLEX_BUILD_DIR}"
        else
            log "  cmake -S ${SOURCE_ROOT} -B ${PHLEX_BUILD_DIR}"
        fi
        if command -v ninja &> /dev/null; then
            log "  ninja -C ${PHLEX_BUILD_DIR}"
        else
            log "  cmake --build ${PHLEX_BUILD_DIR} -j \$(nproc)"
        fi
        echo ""
    fi

    # Clean up and return success
    trap - ERR
    return 0
}

# Run main setup and capture result
main_setup
setup_result=$?

# Clean up error trap
trap - ERR

# Return the result
return $setup_result
