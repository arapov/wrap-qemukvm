#!/usr/bin/bash

# LIBVIRT have kernels/ and images/ dirs.

# CONFIG:
HOME="/home/anton"
LIBVIRT="/home/anton/share/libvirt"

# DEFAULTS:
IFACE="em1"
EXPORT=$HOME
KERNEL=$HOME/src/upstream/linux/arch/x86/boot/bzImage
INITRD=""
IMAGE=$LIBVIRT/images/rawhide.qcow2.img
#ROOT="UUID=f23778d1-d14d-48e0-aeda-52b2158538bc"
ROOT="/dev/vda2"

# Script must be run under superuser
sudo id
[ $? -ne 0 ] && exit 1

# GETOPT:
while getopts "n:e:k:i:s" opt; do
	case $opt in
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


# Defaults for qemu-kvm
CLI_DEFAULTS="-device piix3-usb-uhci,id=usb,bus=pci.0,addr=0x1.0x2 -device virtio-serial-pci,id=virtio-serial0,bus=pci.0,addr=0x5 -device virtio-balloon-pci,id=balloon0,bus=pci.0,addr=0x6"
# CPU
CLI_CPU="-smp 2,sockets=2,cores=1,threads=1 -cpu host,+lahf_lm,+rdtscp,+avx,+osxsave,+xsave,+aes,+popcnt,+x2apic,+sse4.2,+sse4.1,+pdcm,+xtpr,+cx16,+tm2,+est,+smx,+vmx,+ds_cpl,+dtes64,+pclmuldq,+pbe,+tm,+ht,+ss,+acpi,+ds"
# IMAGE
CLI_HDD="-device virtio-blk-pci,scsi=off,bus=pci.0,addr=0x4,drive=drive-virtio-disk0,id=virtio-disk0,bootindex=1 -drive file=$IMAGE,if=none,id=drive-virtio-disk0,format=qcow2"

# Do we want custom kernel?
if [ "$KERNEL" != "" ]; then
	CLI_BOOT="-append 'root=$ROOT ro rd.md=0 rd.lvm=0 rd.dm=0 SYSFONT=True KEYTABLE=us rd.luks=0 LANG=en_US.UTF-8 console=ttyS0 3'"

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
		sudo ip link set macvtap0 address 1a:46:0b:ca:bc:7b up >/dev/null 2>&1
		[ $? -eq 0 ] && echo "OK" || echo "ERROR"
	fi
	NN=`ip link show macvtap0 | head -n 1 | cut -d ":" -f 1`
	TAP=/dev/tap$DESC
	CLI_NETWORK="-netdev tap,id=hostnet0,vhost=on,fd=21 -device virtio-net-pci,netdev=hostnet0,id=net0,mac=1a:46:0b:ca:bc:7b,bus=pci.0,addr=0x3 21<>/dev/tap$NN"
fi

# Do we want export?
[ -d $EXPORT ] && CLI_EXPORT="-fsdev local,security_model=passthrough,id=fsdev-fs0,path=$EXPORT -device virtio-9p-pci,id=fs0,fsdev=fsdev-fs0,mount_tag=host,bus=pci.0,addr=0x7"
echo "[INFO] Exported directory: $EXPORT (alias: host)"
echo "       $ mount -t 9p -o trans=virtio host /mnt/hostfs/ -oversion=9p2000.L"
echo "[INFO] Image to boot: $IMAGE"
echo "       UUID of the / (root) partition: $ROOT_UUID"

CLI_SERIAL="-monitor telnet:127.0.0.1:4444,server,nowait -serial file:/tmp/serial"
#CLI_SERIAL="-serial tcp:127.0.0.1:9999" # nc -l 9999 | tee /tmp/serial

##############

echo "[INFO] KVM start"
sudo su -c "qemu-kvm -M pc-0.15 -enable-kvm -rtc base=utc -m 2048 \
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

