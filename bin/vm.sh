#!/usr/bin/bash

# LIBVIRT have kernels/ and images/ dirs.

# CONFIG:
HOME=/home/devel
LIBVIRT=$HOME/libvirt
IMAGES=$LIBVIRT/images
LINUX=$HOME/up/linux

# DEFAULTS:
IFACE="em1"
EXPORT=$HOME
KERNEL=$LINUX/arch/x86/boot/bzImage
INITRD=""

# IMAGE=(distro).(vmarch).(format)
VMARCH="x86_64"
DISTRO="fedora19"
FMT="qcow2.img"
IMAGE=$LIBVIRT/images/fedora19.x86_64.qcow2.img

#ROOT="UUID=d868faf7-ae27-416a-86ea-7ac01d08d481"
ROOT="/dev/vda3"

# Script must be run under superuser
sudo id
[ $? -ne 0 ] && exit 1

# GETOPT:
while getopts "a:n:e:k:i:s" opt; do
	case $opt in
		a)
			# ARCH
			ARCHBITS=$OPTARG
			;;
		n)
			# Network interface
			IFACE=$OPTARG
			;;
		e)
			EXPORT=$OPTARG
			;;
		k)
			KERNEL=$OPTARG
			;;
		i)
			INITRD=$OPTARG
			;;
		s)
			# selfcontained, use kernel available inside the image:
			KERNEL=""
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&4
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			exit 1
			;;
	esac
done

[ "$ARCHBITS" == "32" ] && VMARCH="i686"
[ "$ARCHBITS" == "64" ] && VMARCH="x86_64"
IMAGE=$IMAGES/$DISTRO.$VMARCH.$FMT

# Defaults for qemu-kvm
CLI_DEFAULTS="-device piix3-usb-uhci,id=usb,bus=pci.0,addr=0x1.0x2 -device virtio-serial-pci,id=virtio-serial0,bus=pci.0,addr=0x4 -device virtio-balloon-pci,id=balloon0,bus=pci.0,addr=0x6"
# CPU
CLI_CPU="-smp 2,sockets=2,cores=1,threads=1 -cpu host,+lahf_lm,+rdtscp,+avx,+osxsave,+xsave,+aes,+popcnt,+x2apic,+sse4.2,+sse4.1,+pdcm,+xtpr,+cx16,+tm2,+est,+smx,+vmx,+ds_cpl,+dtes64,+pclmuldq,+pbe,+tm,+ht,+ss,+acpi,+ds,level=9"
# IMAGE
CLI_HDD="-device virtio-blk-pci,scsi=off,bus=pci.0,addr=0x5,drive=drive-virtio-disk0,id=virtio-disk0,bootindex=1 -drive file=$IMAGE,if=none,id=drive-virtio-disk0,format=qcow2"

# Do we want custom kernel?
CLI_BASE=""
if [ "$KERNEL" != "" ]; then
	CLI_BOOT="-append 'root=$ROOT ro rootflags=subvol=root rd.md=0 rd.lvm=0 rd.dm=0 rd.luks=0 console=ttyS0 3'"
	CLI_BASE="-nographic"
	CLI_KERNEL="-kernel $KERNEL"
	echo "[INFO] Linux kernel to load: $KERNEL"

	if [ "$INITRD" != "" ]; then
		CLI_INITRD="-initrd $INITRD"
		echo "[INFO] Initramfs to load: $INITRD"
	fi
else
	echo "[INFO] Use kernel available in the image"
fi

# Do we want network?
if [ "$IFACE" != "" ]; then
	ip link show macvtap0 >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo -n "[INFO] Setting up bridge interface... "
		sudo ip link add link $IFACE dev macvtap0 type macvtap >/dev/null 2>&1
		sudo ip link set macvtap0 address 52:54:00:5a:1e:e1 up >/dev/null 2>&1
		[ $? -eq 0 ] && echo "OK" || echo "ERROR"
	fi
	NN=`ip link show macvtap0 | head -n 1 | cut -d ":" -f 1`
	TAP=/dev/tap$DESC
	CLI_NETWORK="-netdev tap,id=hostnet0,vhost=on,fd=21 -device virtio-net-pci,netdev=hostnet0,id=net0,mac=52:54:00:5a:1e:e1,bus=pci.0,addr=0x3 21<>/dev/tap$NN"
fi

# Do we want export?
[ -d $EXPORT ] && CLI_EXPORT="-fsdev local,security_model=passthrough,id=fsdev-fs0,path=$EXPORT -device virtio-9p-pci,id=fs0,fsdev=fsdev-fs0,mount_tag=host,bus=pci.0,addr=0x7"
echo "[INFO] Exported directory: $EXPORT (alias: host)"
echo "       $ mount -t 9p -o trans=virtio host /mnt/hostfs/ -oversion=9p2000.L"
echo "[INFO] Image to boot: $IMAGE"
echo "       UUID of the / (root) partition: $ROOT_UUID"

CLI_SERIAL=""
#CLI_SERIAL="-monitor telnet:127.0.0.1:4444,server,nowait -serial file:/tmp/serial"
#CLI_SERIAL="-serial tcp:127.0.0.1:9999" # nc -l 9999 | tee /tmp/serial

##############

echo "[INFO] KVM start"
sudo su -c "qemu-kvm -name f18.x86_64 -M pc-1.2 -enable-kvm -rtc base=utc -m 2048 \
			$CLI_BASE \
			$CLI_KERNEL \
			$CLI_INITRD \
			$CLI_CPU \
			$CLI_DEFAULTS \
			$CLI_EXPORT \
			$CLI_HDD \
			$CLI_BOOT \
			$CLI_SERIAL \
			$CLI_NETWORK" # NETWORK MUST BE LAST DUE TO PIPE
echo "[INFO] KVM stop"

if [ "$IFACE" != "" ]; then
	echo -n "[INFO] Removing bridged network interface... "
	sudo ip link delete macvtap0
	[ $? -eq 0 ] && echo "OK" || echo "ERROR"
fi

exit 0;

