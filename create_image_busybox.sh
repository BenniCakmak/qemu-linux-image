#!/bin/bash

# Ensure the script is run with superuser privileges
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# List of required commands
REQUIRED_COMMANDS=(wget dpkg dd mkfs.ext4 mount umount qemu-system-x86_64)

# Check if all required commands are available
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

# Function to print debug messages if VERBOSE is set (sudo VERBOSE=1 ./create_image.sh)
debug() {
    if [[ -n "$VERBOSE" ]]; then
        echo "DEBUG: $1"
    fi
}

# Set up variables
KERNEL_URL="https://kernel.ubuntu.com/mainline/v6.10.2/amd64/linux-image-unsigned-6.10.2-061002-generic_6.10.2-061002.202407271100_amd64.deb"
BUSYBOX_URL="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
IMAGE="filesystem.img"
MOUNT_POINT="/mnt/qemu"

# Ensure no working directory exists before creating it
if [ -d "working" ]; then
    debug "Removing existing working directory"
    rm -rf working
fi

# Create a working directory
mkdir -p working
cd working

# Download and extract the kernel
debug "Downloading kernel from: $KERNEL_URL"
wget $KERNEL_URL -O linux-image.deb
debug "Extracting kernel"
dpkg -x linux-image.deb linux-image

# Download BusyBox
debug "Downloading BusyBox from: $BUSYBOX_URL"
wget $BUSYBOX_URL -O busybox
chmod +x busybox

# Create an empty disk image
debug "Creating empty disk image: $IMAGE"
dd if=/dev/zero of=$IMAGE bs=1M count=1024

# Create a filesystem on the image
debug "Creating filesystem on the image"
mkfs.ext4 $IMAGE

# Mount the image
mkdir -p $MOUNT_POINT
debug "Mounting the image"
mount -o loop $IMAGE $MOUNT_POINT

# Create a basic filesystem structure
debug "Creating basic filesystem structure"
mkdir -p $MOUNT_POINT/{bin,sbin,etc,proc,sys,usr/{bin,sbin}}

# Copy the kernel to the image
debug "Copying kernel to the image"
mkdir -p $MOUNT_POINT/boot
cp linux-image/boot/vmlinuz-* $MOUNT_POINT/boot/

# Copy BusyBox binary
debug "Copying BusyBox to the image"
cp busybox $MOUNT_POINT/bin/
ln -s /bin/busybox $MOUNT_POINT/bin/sh
ln -s /bin/busybox $MOUNT_POINT/bin/echo

# Create init script to print "hello world"
debug "Creating init script"
echo -e "#!/bin/sh\n\necho 'hello world'\n\nexec /bin/sh" > $MOUNT_POINT/init
chmod +x $MOUNT_POINT/init

# Unmount the image
debug "Unmounting the image"
umount $MOUNT_POINT

# Run the image with QEMU
debug "Running the image with QEMU"
qemu-system-x86_64 -kernel linux-image/boot/vmlinuz-* -append "console=ttyS0 root=/dev/sda init=/init" -hda $IMAGE -serial mon:stdio -nographic

# Cleanup
debug "Cleaning up working directory"
cd ..
rm -rf working
