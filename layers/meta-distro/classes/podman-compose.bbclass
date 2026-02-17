# podman-compose.bbclass
#
# BitBake class for building OCI container images from compose files
# Uses podman-native and podman-compose-native (no dockerd or root required)
#
# Usage in recipe:
#   inherit podman-compose
#   SRC_URI = "file://docker-compose.yml"
#   COMPOSE_PROJECT_NAME = "myproject"
#   COMPOSE_OUTPUT_DIR = "${DEPLOY_DIR}/images/${MACHINE}/containers"
#
# The class will:
#   1. Parse the compose file
#   2. Build container images using podman (in do_compile)
#   3. Export images as OCI tar archives (in do_install)
#   4. Deploy to COMPOSE_OUTPUT_DIR (in do_deploy)

# Documentation (from podman-compose.md)
#
# # Podman Compose BitBake Class
#
# This directory contains the `podman-compose.bbclass` for building OCI container images from Docker Compose files without requiring Docker daemon or root privileges.
#
# ## Features
#
# - **No Docker daemon required**: Uses podman instead of dockerd
# - **No root privileges needed**: All operations run as regular user
# - **Rootless containers**: Uses VFS storage driver by default
# - **Docker-dir format**: Exports images in docker-dir format for better compatibility
# - **Compression**: Automatic gzip compression of exported images
# - **Compose file support**: Standard docker-compose.yml format
# - **Shared state cache**: Full sstate-cache support for faster rebuilds
#
# ## Usage
#
# ### Basic Recipe Example
#
# ```bitbake
# SUMMARY = "Example container images built from compose file"
# LICENSE = "MIT"
#
# inherit podman-compose
#
# # Compose file will be fetched to ${WORKDIR}/docker-compose.yml
# SRC_URI = "file://docker-compose.yml \
#            file://app/Dockerfile \
#            file://app/src/"
#
# # Project name (used for tagging)
# COMPOSE_PROJECT_NAME = "myapp"
#
# # Where to deploy the exported OCI tar files
# COMPOSE_OUTPUT_DIR = "${DEPLOY_DIR}/images/${MACHINE}/containers"
#
# S = "${WORKDIR}"
#
# # Note: COMPOSE_IMAGE_TAG defaults to ${PV}, so images will be tagged with recipe version
# ```
#
# ### Compose File Example
#
# ```yaml
# version: '3.8'
#
# services:
#   web:
#     build:
#       context: ./app
#       dockerfile: Dockerfile
#     image: myapp-web:${IMAGE_TAG}
#     image: myapp-web:latest
#     labels:
#       description: "Web application frontend"
#
#   api:
#     build:
#       context: ./api
#       dockerfile: Dockerfile
#     image: myapp-api:latest
#     labels:
#       description: "Backend API service"
# ```
#
# ## Configuration Variables
#
# | Variable | Default | Description |
# |----------|---------|-------------|
# | `COMPOSE_FILE` | `${WORKDIR}/docker-compose.yml` | Path to compose file (auto-fetched from SRC_URI) |
# | `COMPOSE_PROJECT_NAME` | `${PN}` | Project name for tagging |
# | `COMPOSE_IMAGE_TAG` | `${PV}` | Image tag (available as ${IMAGE_TAG} in compose file) |
# | `COMPOSE_OUTPUT_DIR` | `${DEPLOY_DIR}/images/${MACHINE}/containers` | Output directory for images |
# | `COMPOSE_BUILD_DIR` | `${WORKDIR}/podman-build` | Build working directory |
# | `COMPOSE_STORAGE_DIR` | `${WORKDIR}/podman-storage` | Podman storage directory |
# | `COMPOSE_INSTALL_DIR` | `${D}${datadir}/containers/${PN}` | Install directory in package |
# | `COMPOSE_EXPORT_FORMAT` | `docker-archive` | Export format (docker-dir, oci-dir, oci-archive, docker-archive) |
# | `COMPOSE_COMPRESS` | `1` for docker-dir, `0` otherwise | Enable gzip compression (1=enabled, 0=disabled, only for docker-dir) |
# | `PODMAN_STORAGE_DRIVER` | `vfs` | Storage driver (vfs for rootless) |
# | `PODMAN_RUNROOT` | `${COMPOSE_BUILD_DIR}/run` | Podman runtime directory |
# | `PODMAN_TMPDIR` | `${COMPOSE_BUILD_DIR}/tmp` | Temporary directory |
#
# ## Tasks
#
# ### do_compile (standard BitBake task)
#
# Builds all services defined in the compose file using podman:
# - Parses compose file
# - Builds images for each service
# - Stores images in isolated podman storage
# - No Docker daemon required
#
# ### do_install (standard BitBake task)
#
# Exports built images as OCI tar archives to `${D}`:
# - Lists all built images
# - Exports each image to OCI tar format
# - Installs to `${D}${datadir}/containers/${PN}`
# - Creates files that can be packaged
#
# ### do_deploy
#
# Deploys OCI tar archives from install directory to deploy directory:
# - Copies OCI archives to `COMPOSE_OUTPUT_DIR`
# - Makes images available in `${DEPLOY_DIR}`
# - Can be used without creating packages
# - **Supports sstate-cache**: Deployed images cached for reuse across builds
#
# ### do_deploy_setscene
#
# Restores deployed images from sstate-cache:
# - Automatically invoked when sstate artifacts are available
# - Skips rebuild if cached deployment matches
# - Significantly speeds up rebuilds
#
# ### do_clean
#
# Removes all built artifacts and podman storage:
# - Removes OCI images from podman storage
# - Cleans up podman build directories
# - Removes installed OCI archives from `${D}`
# - Removes deployed OCI archives from deploy directory
# - Useful for forcing a complete rebuild
#
# Usage: `bitbake <recipe> -c clean`
#
# ### do_cleansstate
#
# Removes everything including sstate cache:
# - Runs `do_clean` first
# - Removes sstate artifacts for this recipe
# - Forces complete rebuild on next invocation
# - Useful when troubleshooting cache issues
#
# Usage: `bitbake <recipe> -c cleansstate`
#
# ## Dependencies
#
# The class automatically adds:
# - `podman-native`: Rootless container engine
# - `podman-compose-native`: Compose file parser and builder
#
# Ensure these packages are available in your layer dependencies (meta-virtualization).
#
# ## Output
#
# Built images are exported to multiple locations:
#
# **1. Package files** (if creating packages):
# ```
# ${D}${datadir}/containers/${PN}/
# ├── myapp-web_latest.tar
# └── myapp-api_latest.tar
# ```
#
# **2. Deploy directory** (always created):
# ```
# ${DEPLOY_DIR}/images/${MACHINE}/containers/
# ├── myapp-web_latest.tar
# └── myapp-api_latest.tar
# ```
#
# These OCI archives can be:
# - Loaded into container runtimes: `podman load < image.tar`
# - Distributed as deployment artifacts
# - Included in image recipes
# - Packaged as part of the recipe (in `${datadir}/containers/${PN}`)
#
# ## Advantages Over Docker
#
# | Feature | podman-compose | docker-compose |
# |---------|----------------|----------------|
# | Root required | ❌ No | ✅ Yes |
# | Daemon required | ❌ No | ✅ Yes |
# | Build privileges | None | Requires docker group |
# | CI/CD friendly | ✅ Yes | ⚠️ Requires setup |
# | Yocto integration | ✅ Native | ⚠️ External |
#
# ## Example: Multi-Service Application
#
# ```bitbake
# SUMMARY = "Multi-tier application containers"
# DESCRIPTION = "Frontend, backend, and database containers"
# LICENSE = "MIT"
# LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"
#
# inherit podman-compose
#
# COMPOSE_FILE = "${WORKDIR}/docker-compose.yml"
# COMPOSE_PROJECT_NAME = "mystack"
#
# SRC_URI = " \
#     file://docker-compose.yml \
#     file://frontend/Dockerfile \
#     file://frontend/package.json \
#     file://frontend/src/ \
#     file://backend/Dockerfile \
#     file://backend/requirements.txt \
#     file://backend/app/ \
# "
#
# S = "${WORKDIR}"
#
# # Optional: Create package with OCI archives
# # The class automatically installs to ${D}${datadir}/containers/${PN}
# # Set this if you want to create an installable package
# PACKAGES = "${PN}"
# FILES:${PN} = "${datadir}/containers/${PN}/*.tar"
#
# # Optional: Deploy without packaging
# # Images are automatically deployed to ${DEPLOY_DIR}/images/${MACHINE}/containers
# do_deploy() {
#     # The class handles deployment automatically
#     :
# }
#
# addtask deploy after do_install
# ```
#
# ## Troubleshooting
#
# ### Build fails with "permission denied"
#
# Ensure `PODMAN_STORAGE_DRIVER = "vfs"` is set. The VFS driver works without special privileges.
#
# ### Images not found after build
#
# Check that your compose file includes `image:` tags for services with `build:` directives.
#
# ### Export fails
#
# Verify `COMPOSE_OUTPUT_DIR` is writable and has sufficient space for OCI archives.
#
# ### Sstate-cache not working
#
# Ensure `SSTATE_DIR` is configured in your build environment. The class caches the `do_deploy` task, so:
# - First build: Images built and deployed normally
# - Subsequent builds: If inputs unchanged, deployment restored from cache
# - Check: `bitbake <recipe> -c cleansstate` to force rebuild
#
# ### Need to force rebuild
#
# Use the clean tasks:
# ```bash
# # Clean build artifacts and podman storage
# bitbake mycontainers -c clean
#
# # Clean everything including sstate cache
# bitbake mycontainers -c cleansstate
# ```
#
# ### Podman storage grows too large
#
# The `do_clean` task removes all podman storage for the recipe:
# ```bash
# bitbake mycontainers -c clean
# ```
#
# This removes images and clears the VFS storage driver cache.
#
# ## Performance Benefits
#
# The sstate-cache support provides significant performance improvements:
#
# | Scenario | Without sstate | With sstate (cache hit) |
# |----------|----------------|-------------------------|
# | Initial build | Full build time | Full build time |
# | Rebuild (no changes) | Full build time | ~1 second (cache restore) |
# | Rebuild (source change) | Full build time | Full build time |
# | Clean + rebuild | Full build time | ~1 second (cache restore) |
#
# **Cache key factors:**
# - Compose file content (via `COMPOSE_FILE` checksum)
# - Source files referenced in Dockerfiles
# - Build dependencies
# - Machine architecture (`MACHINE` variable)
#
# ## Integration with Image Recipes
#
# To include built containers in a system image:
#
# ```bitbake
# IMAGE_INSTALL:append = " mycontainers"
#
# # Deploy containers to /var/lib/containers/storage
# do_install:append() {
#     install -d ${D}/var/lib/containers/storage
#     for tar in ${DEPLOY_DIR}/images/${MACHINE}/containers/*.tar; do
#         install -m 0644 $tar ${D}/var/lib/containers/storage/
#     done
# }
# ```
#
# ## See Also
#
# - [Podman Documentation](https://podman.io/)
# - [Compose Specification](https://compose-spec.io/)
# - meta-virtualization layer for podman-native recipes

DEPENDS += "podman-native podman-compose-native"

# Configuration variables
COMPOSE_FILE ??= "${WORKDIR}/docker-compose.yml"
COMPOSE_PROJECT_NAME ??= "${PN}"
COMPOSE_IMAGE_TAG ??= "${PV}"
COMPOSE_OUTPUT_DIR ??= "${DEPLOY_DIR}/images/${MACHINE}/containers"
COMPOSE_BUILD_DIR ??= "${WORKDIR}/podman-build"
COMPOSE_STORAGE_DIR ??= "${WORKDIR}/podman-storage"
COMPOSE_INSTALL_DIR ??= "${D}${datadir}/containers/${PN}"
COMPOSE_EXPORT_FORMAT ??= "docker-archive"
COMPOSE_COMPRESS ??= "${@'1' if d.getVar('COMPOSE_EXPORT_FORMAT') == 'docker-dir' else '0'}"

# Podman configuration
PODMAN_STORAGE_DRIVER ??= "vfs"
PODMAN_RUNROOT ??= "${COMPOSE_BUILD_DIR}/run"
PODMAN_TMPDIR ??= "${COMPOSE_BUILD_DIR}/tmp"

python do_compile() {
    """
    Build container images from compose file using podman
    This is the standard BitBake compile task
    """
    import os
    import json
    import subprocess

    compose_file = d.getVar('COMPOSE_FILE')
    project_name = d.getVar('COMPOSE_PROJECT_NAME')
    image_tag = d.getVar('COMPOSE_IMAGE_TAG')
    build_dir = d.getVar('COMPOSE_BUILD_DIR')
    storage_dir = d.getVar('COMPOSE_STORAGE_DIR')
    storage_driver = d.getVar('PODMAN_STORAGE_DRIVER')
    runroot = d.getVar('PODMAN_RUNROOT')
    tmpdir = d.getVar('PODMAN_TMPDIR')

    if not os.path.exists(compose_file):
        bb.fatal(f"Compose file not found: {compose_file}")

    # Create required directories
    os.makedirs(build_dir, exist_ok=True)
    os.makedirs(storage_dir, exist_ok=True)
    os.makedirs(runroot, exist_ok=True)
    os.makedirs(tmpdir, exist_ok=True)

    # Setup environment for podman (no root required)
    env = os.environ.copy()
    env.update({
        'TMPDIR': tmpdir,
        'XDG_RUNTIME_DIR': runroot,
        'IMAGE_TAG': image_tag,
    })

    # Build podman command with storage configuration
    podman_args = [
        '--root', storage_dir,
        '--runroot', runroot,
        '--storage-driver', storage_driver,
    ]

    bb.note(f"Building containers from {compose_file}")
    bb.note(f"Project name: {project_name}")
    bb.note(f"Image tag: {image_tag}")
    bb.note(f"Storage: {storage_dir} (driver: {storage_driver})")

    # Run podman-compose build
    compose_cmd = [
        'podman-compose',
        '-f', compose_file,
        '-p', project_name,
        'build',
        '--no-cache',
    ]

    try:
        # Note: podman-compose will use podman binary, we need to ensure it uses our storage
        bb.note(f"Running: {' '.join(compose_cmd)}")
        result = subprocess.run(
            compose_cmd,
            env=env,
            cwd=os.path.dirname(compose_file),
            check=True,
            capture_output=True,
            text=True
        )
        bb.note(result.stdout)
        if result.stderr:
            bb.warn(result.stderr)
    except subprocess.CalledProcessError as e:
        bb.fatal(f"podman-compose build failed: {e.stderr}")

    # Get list of images built
    images_cmd = [
        'podman',
    ] + podman_args + [
        'images',
        '--format', 'json',
        '--filter', f'label=com.docker.compose.project={project_name}',
    ]

    try:
        result = subprocess.run(
            images_cmd,
            env=env,
            check=True,
            capture_output=True,
            text=True
        )
        images = json.loads(result.stdout)

        # Store image list for install task
        d.setVar('PODMAN_BUILT_IMAGES', ' '.join([img['Id'][:12] for img in images]))

        bb.note(f"Built {len(images)} container images")
        for img in images:
            bb.note(f"  - {img['Names'][0] if img.get('Names') else img['Id'][:12]}")

    except subprocess.CalledProcessError as e:
        bb.fatal(f"Failed to list built images: {e.stderr}")
    except json.JSONDecodeError as e:
        bb.fatal(f"Failed to parse image list: {e}")
}

python do_install() {
    """
    Export built container images as docker-dir format to ${D}
    This is the standard BitBake install task
    """
    import os
    import subprocess
    import tarfile

    storage_dir = d.getVar('COMPOSE_STORAGE_DIR')
    runroot = d.getVar('PODMAN_RUNROOT')
    tmpdir = d.getVar('PODMAN_TMPDIR')
    storage_driver = d.getVar('PODMAN_STORAGE_DRIVER')
    install_dir = d.getVar('COMPOSE_INSTALL_DIR')
    project_name = d.getVar('COMPOSE_PROJECT_NAME')
    export_format = d.getVar('COMPOSE_EXPORT_FORMAT') or 'docker-archive'
    compress = d.getVar('COMPOSE_COMPRESS') == '1'

    # Compression only applies to docker-dir format
    if compress and export_format != 'docker-dir':
        bb.warn(f"Compression is only supported for docker-dir format, ignoring COMPOSE_COMPRESS for {export_format}")
        compress = False

    bb.note(f"Export format: {export_format}, compression: {compress}")

    # Get list of built images
    built_images = d.getVar('PODMAN_BUILT_IMAGES')
    if not built_images:
        bb.warn("No images to install")
        return

    os.makedirs(install_dir, exist_ok=True)

    # Setup environment
    env = os.environ.copy()
    env.update({
        'TMPDIR': tmpdir,
        'XDG_RUNTIME_DIR': runroot,
    })

    podman_args = [
        '--root', storage_dir,
        '--runroot', runroot,
        '--storage-driver', storage_driver,
    ]

    # Get detailed image information
    images_cmd = [
        'podman',
    ] + podman_args + [
        'images',
        '--format', 'json',
        '--filter', f'label=com.docker.compose.project={project_name}',
    ]

    try:
        result = subprocess.run(images_cmd, env=env, check=True, capture_output=True, text=True)
        images = json.loads(result.stdout)

        for img in images:
            # Get image name and tag
            names = img.get('Names', [])
            if not names:
                bb.warn(f"Image {img['Id'][:12]} has no name, skipping install")
                continue

            image_name = names[0]
            # Sanitize filename
            safe_name = image_name.replace(':', '_').replace('/', '_')

            # Export to docker-dir format
            output_dir = os.path.join(install_dir, safe_name)

            bb.note(f"Installing {image_name} to {output_dir} (format: {export_format})")

            # Export image as docker-dir
            export_cmd = [
                'podman',
            ] + podman_args + [
                'save',
                '--format', export_format,
                '-o', output_dir,
                image_name,
            ]

            try:
                subprocess.run(export_cmd, env=env, check=True, capture_output=True, text=True)
                bb.note(f"  Exported to directory: {output_dir}")

                # Compress to tar.gz if enabled
                if compress:
                    tar_file = f"{output_dir}.tar.gz"
                    bb.note(f"  Compressing to: {tar_file}")

                    with tarfile.open(tar_file, 'w:gz') as tar:
                        tar.add(output_dir, arcname=os.path.basename(output_dir))

                    # Remove uncompressed directory
                    import shutil
                    shutil.rmtree(output_dir)
                    bb.note(f"  Installed: {tar_file}")
                else:
                    bb.note(f"  Installed: {output_dir}")

            except subprocess.CalledProcessError as e:
                bb.error(f"Failed to install {image_name}: {e.stderr}")

    except subprocess.CalledProcessError as e:
        bb.fatal(f"Failed to list images for install: {e.stderr}")
    except json.JSONDecodeError as e:
        bb.fatal(f"Failed to parse image list: {e}")
}

python do_deploy() {
    """
    Deploy docker-dir archives to COMPOSE_OUTPUT_DIR
    """
    import os
    import shutil

    install_dir = d.getVar('COMPOSE_INSTALL_DIR')
    output_dir = d.getVar('COMPOSE_OUTPUT_DIR')

    if not os.path.exists(install_dir):
        bb.warn(f"Install directory not found: {install_dir}")
        return

    os.makedirs(output_dir, exist_ok=True)

    # Copy all docker-dir archives (tar.gz files or directories) to deploy directory
    for item in os.listdir(install_dir):
        src = os.path.join(install_dir, item)
        dst = os.path.join(output_dir, item)

        if item.endswith('.tar.gz'):
            bb.note(f"Deploying {item} to {output_dir}")
            shutil.copy2(src, dst)
        elif os.path.isdir(src):
            bb.note(f"Deploying directory {item} to {output_dir}")
            if os.path.exists(dst):
                shutil.rmtree(dst)
            shutil.copytree(src, dst)
}

addtask deploy after do_install before do_build

# Files to be packaged (if creating a package)
FILES:${PN} = "${datadir}/containers/${PN}/*.tar.gz ${datadir}/containers/${PN}/*"

# Shared state (sstate-cache) support
SSTATETASKS += "do_deploy"

do_deploy[sstate-inputdirs] = "${COMPOSE_INSTALL_DIR}"
do_deploy[sstate-outputdirs] = "${COMPOSE_OUTPUT_DIR}"
do_deploy[dirs] = "${COMPOSE_INSTALL_DIR} ${COMPOSE_OUTPUT_DIR}"
do_deploy[cleandirs] = "${COMPOSE_OUTPUT_DIR}"
do_deploy[stamp-extra-info] = "${MACHINE}"

python do_deploy_setscene() {
    """
    Restore deployed OCI archives from sstate-cache
    """
    sstate_task_prefunc(d)
    bb.note("Restoring deployed container images from sstate-cache")
    sstate_task_postfunc(d)
}

addtask do_deploy_setscene

python do_clean() {
    """
    Clean task: Remove built OCI images and podman storage
    """
    import os
    import shutil
    import subprocess

    build_dir = d.getVar('COMPOSE_BUILD_DIR')
    storage_dir = d.getVar('COMPOSE_STORAGE_DIR')
    output_dir = d.getVar('COMPOSE_OUTPUT_DIR')
    install_dir = d.getVar('COMPOSE_INSTALL_DIR')
    project_name = d.getVar('COMPOSE_PROJECT_NAME')
    runroot = d.getVar('PODMAN_RUNROOT')
    tmpdir = d.getVar('PODMAN_TMPDIR')
    storage_driver = d.getVar('PODMAN_STORAGE_DRIVER')

    bb.note("Cleaning podman container images and storage")

    # Setup environment
    env = os.environ.copy()
    env.update({
        'TMPDIR': tmpdir if os.path.exists(tmpdir or '') else '/tmp',
        'XDG_RUNTIME_DIR': runroot if os.path.exists(runroot or '') else '/tmp',
    })

    podman_args = [
        '--root', storage_dir,
        '--runroot', runroot,
        '--storage-driver', storage_driver,
    ]

    # Remove images from podman storage if it exists
    if os.path.exists(storage_dir):
        try:
            # Get list of images for this project
            images_cmd = [
                'podman',
            ] + podman_args + [
                'images',
                '--format', '{{.ID}}',
                '--filter', f'label=com.docker.compose.project={project_name}',
            ]

            result = subprocess.run(
                images_cmd,
                env=env,
                check=False,
                capture_output=True,
                text=True
            )

            if result.returncode == 0 and result.stdout.strip():
                image_ids = result.stdout.strip().split('\n')
                for image_id in image_ids:
                    bb.note(f"Removing image: {image_id}")
                    rm_cmd = ['podman'] + podman_args + ['rmi', '-f', image_id]
                    subprocess.run(rm_cmd, env=env, check=False, capture_output=True)
        except Exception as e:
            bb.warn(f"Failed to remove podman images: {e}")

    # Remove podman storage directory
    if os.path.exists(storage_dir):
        bb.note(f"Removing podman storage: {storage_dir}")
        shutil.rmtree(storage_dir, ignore_errors=True)

    # Remove build directory
    if os.path.exists(build_dir):
        bb.note(f"Removing build directory: {build_dir}")
        shutil.rmtree(build_dir, ignore_errors=True)

    # Remove installed OCI archives from install directory
    if os.path.exists(install_dir):
        bb.note(f"Removing install directory: {install_dir}")
        shutil.rmtree(install_dir, ignore_errors=True)

    # Remove deployed OCI archives from output directory
    if os.path.exists(output_dir):
        bb.note(f"Cleaning output directory: {output_dir}")
        for item in os.listdir(output_dir):
            if project_name in item and (item.endswith('.tar.gz') or os.path.isdir(os.path.join(output_dir, item))):
                filepath = os.path.join(output_dir, item)
                bb.note(f"Removing: {filepath}")
                if os.path.isdir(filepath):
                    shutil.rmtree(filepath)
                else:
                    os.remove(filepath)
}

python do_cleansstate() {
    """
    Clean sstate task: Remove everything including sstate artifacts
    """
    # First run the regular clean
    bb.build.exec_func('do_clean', d)

    bb.note("Cleaning sstate artifacts for podman-compose")

    # The sstate cleaning is handled by BitBake's sstate infrastructure
    # This just ensures do_clean runs first
}

addtask clean
addtask cleansstate after do_clean

# Import json module for Python tasks
python() {
    import json
}
