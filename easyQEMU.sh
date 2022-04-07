#!/usr/bin/env bash

# https://github.com/stylesuxx/amdvbflash/raw/master/amdvbflash
# https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.189-1/virtio-win-0.1.189.iso

# TODO: разобраться почему при перезагрузке гостя изображение не появляется

__filename="$(readlink --canonicalize-existing "$0")";
__dirname="$(dirname "$__filename")";
RUN=$(echo $0 | sed 's/\/usr\/local\/bin\///g' | sed 's/\/dev\/fd\/.*//g');
ARGS=($@);
SUDO="sudo";
cd $__dirname;

case ${ARGS[0]} in
	help )
		# TODO: перевести на англ
		echo '---------------';
		echo 'Help easyQEMU';
		echo '---------------';
		echo "Usage: [env...] $RUN [options...]";
		echo '---------------';
		table=(
			"env"
			" | DISK (string/array) | диски (NULL)"
			" | DISK_SIZE (string) | размер диска при создании (20G)"
			" | CDROM (string/array) | дисководы (NULL)"
			" | CDROM_OFF (boolean) | отключить дисководы (0)"
			# " | HOSTFWD | "
			" | VIRTIO (boolean) | использовать дисковую подсистему virtio, для некоторых ОС нужно установить драйвера (1)"
			" | UEFI (boolean) | запуск в режиме uefi (1)"
			" | VNC_PORT (integer) | запуск vnc на указанном порту (NULL)"
			" | HEADLESS (boolean) | запуск в безголовом режиме (0)"
			" | CPUS (integer/string) | колическо ядер (MAX)"
			" | RAM (integer/string) | колическо оперативной памяти (MAX)"
			" | PCI (array) | устройства которые нужно перебросить (NULL)"
			"options"
			" | help | показать помощь"
			# " | install | установить со всеми зависимостями"
			# " | gui | запуск в графическом режиме"
			# " | mount <img> | смонтировать img файл для чтения, при прерывании размонтировать"
			" | list | список виртуальных машин"
			# " | create | создать виртуальную машину"
			# " | remove <wm> | удалить виртуальную машину"
			" | status <wm> | статус виртуальной машины"
			" | start <wm> | запустить виртуальную машину"
			" | stop <wm> | остановить виртуальную машину"
		);
		printf "%s\n" "${table[@]}" | column -t -s '|';
		exit;
	;;
	install )
		# TODO
		# Запрашивать место установки (аргумент --dst), если пуст то по умолчанию /opt/
		# Если метка диска Ventoy, то создать bios, img, iso, qemu, ventoy
		# Копируем себя в qemu/easyQEMU.sh и создаем символическую ссылку если надо в /usr/local/bin/easyQEMU
		# Внутри qemu - logs, vm, tools
		# В ventoy скачать ventoy_vhdboot.img
		# В tools скачать amdvbflash, virtio-win.iso, vtoyboot.iso
		# В tools/versions.ini записать версии amdvbflash, virtio-win, ventoy, vtoyboot, ventoy_vhdboot
		# Если метка не совпадает, то bios, img внутри, а vtoyboot.iso не скачивать
		if [ $(id -u) -ne 0 ]; then
			mkdir -p ./vm/ ./logs/ ./tools/; # Если на раздел с ventoy, то рут не нужен
			$SUDO $RUN ${ARGS[@]};
		else
			if [ ! -z $(type -p apt) ]; then
				if [[ "$(( $(date +%s) - $(stat -c %Y /var/cache/apt/pkgcache.bin) ))" -gt 12*60*60 ]]; then
					apt-get update;
				fi
				apt install at qemu-system kpartx -y;
				if [ -r "/etc/kernelstub/configuration" ]; then # Pop_OS
					apt install jq -y;
				fi
				if [ ! -z $(type -p nautilus) ] && [ -z $(type -p samba) ] && [ ! -z "$SUDO_USER" ]; then
					apt install samba nautilus-share -y;
					systemctl enable smb;
					useradd -M $SUDO_USER;
					smbpasswd -a $SUDO_USER;
				fi
			fi
			usermod -aG kvm $SUDO_USER;
			vendor=$(egrep '^(vendor_id|Hardware)' /proc/cpuinfo | cut -f2 -d: | sort -u | sed 's/.*\(Genuine\|Authentic\)//g; s/[[:space:]]\+//g;' | tr '[A-Z]' '[a-z]');
			if [ "$vendor" != "intel" ] && [ "$vendor" != "amd" ]; then
				echo "[ERROR] cpu vendor: $vendor";
				exit 1;
			fi
			# TODO: добавить другие дистрибутивы (manjaro, fedora)
			if [ -r "/etc/kernelstub/configuration" ]; then # Pop_OS
				fconf="/etc/kernelstub/configuration";
				conf=$(cat $fconf);
				# if [ $(echo $conf | grep -c "iommu") = 0 ]; then
				if [[ ! "$conf" =~ 'iommu' ]]; then
					(echo $conf | jq --arg vendor $vendor'_iommu=on' '.user.kernel_options |= .+ [$vendor,"iommu=pt"]') > $fconf;
					update-initramfs -c -k all;
				fi
			elif [ -r "/etc/default/grub" ]; then # Ubuntu
				if [[ ! "$(cat /etc/default/grub)" =~ 'iommu' ]]; then
					sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*/& ${vendor}_iommu=on iommu=pt/" /etc/default/grub;
					sudo update-grub;
				fi
			fi
		fi
		exit;
	;;
	gui )
		echo "TODO: GUI";
		exit;
	;;
	mount )
		if [ $(id -u) -ne 0 ]; then
			$SUDO $RUN ${ARGS[@]};
		else
			# '' - поле ввода
			# '-l' - монтировать
			# '-u' - размонтировать
			# '-p' - путь монтировать
			[ ! -z "${ARGS[1]}" ] && DISK="${ARGS[1]}";
			if [ -z "$DISK" ]; then
				echo '[ERROR] Empty path disk';
			else
				if [[ $DISK == *sh ]]; then
					DISK="$(basename ${DISK%.*})";
				fi
				if [ -r "./vm/$DISK.sh" ]; then
					name=$DISK;
					unset DISK;
					source ./vm/$name.sh;
				fi
				if [ ! -r "$DISK" ] && [[ "$DISK" =~ '/media/' ]]; then
					# IFS='/' read -a path <<< $DISK
					readarray -td / path < <(printf '%s' "$DISK");
					# TODO: Поддержка /dev/disk/by-uuid/
					if [ -L "/dev/disk/by-label/${path[3]}" ] && [[ ! "$(mount)" =~ "/${path[1]}/${path[2]}/${path[3]}" ]]; then
						echo "[MOUNT DRIVE] /dev/disk/by-label/${path[3]} => /${path[1]}/${path[2]}/${path[3]}";
						mkdir -p /${path[1]}/${path[2]}/${path[3]} || exit 1;
						mount /dev/disk/by-label/${path[3]} /${path[1]}/${path[2]}/${path[3]} || exit 1;
					fi
				fi
			fi
		fi
		exit;
	;;
	list )
		if [ $(id -u) -ne 0 ]; then
			$SUDO $RUN ${ARGS[@]};
		else
			table="NAME | STATUS\n";
			shopt -s nullglob;
			files=(./vm/*.sh);
			shopt -u nullglob;
			if [ ! -z "$files" ]; then
				for file in "${files[@]}"; do
					NAME="$(basename ${file%.*})";
					fpid="${TMPDIR:-/tmp}/qemu_$NAME.pid";
					state="-";
					if [ -f "$fpid" ]; then
						pid=$(cat "$fpid");
						if [ ! -z "$pid" ] && [ -d "/proc/$pid" ]; then
							state="+";
						fi
					fi
					table+="$NAME | [ $state ] \n";
				done
				printf "$table" | column -t -s '|';
			else
				echo "Empty list";
			fi
		fi
		exit;
	;;
	create )
		echo "TODO: CREATE";
		# TODO:
		# Создавать скрипт ./vm/$name.sh
		# Запрашивать добавить ли в файл ventoy_grub.cfg
		# Предлагать скачать готовые iso, img - chromeos, popos и тд
		exit;
	;;
	remove )
		echo "TODO: remove";
		# TODO:
		# Удалить ./vm/$name.sh и предложить удалить файлы
		exit;
	;;
	status )
		[ ! -z "${ARGS[1]}" ] && NAME="$(basename ${ARGS[1]%.*})";
		if [ -z "$NAME" ]; then
			echo '[ERROR] Empty name vm';
		else
			if [ ! -r "./vm/$NAME.sh" ]; then
				echo "[ERROR] Not found vm: $NAME";
			else
				source ./vm/$NAME.sh;
				if ([[ "${DISK[@]}" =~ '/dev/' ]] || [ ! -z "$PCI" ]) && [ $(id -u) -ne 0 ]; then
					$SUDO $RUN ${ARGS[@]};
				else
					echo "[STATUS] VM name: $NAME";
					pid=;
					state=0;
					fpid="${TMPDIR:-/tmp}/qemu_$NAME.pid";
					if [ -f "$fpid" ]; then
						pid=$(cat "$fpid");
						if [ ! -z "$pid" ] && [ -d "/proc/$pid" ]; then
							state=1;
						fi
					fi
					if [ $state -eq 1 ]; then
						echo "vm is running at process id $pid";
					else
						echo "vm is not running";
					fi
				fi
			fi
		fi
		exit;
	;;
	start )
		[ ! -z "${ARGS[1]}" ] && NAME="$(basename ${ARGS[1]%.*})";
		if [ -z "$NAME" ]; then
			echo '[ERROR] Empty name vm';
		else
			if [ ! -r "./vm/$NAME.sh" ]; then
				echo "[ERROR] Not found vm: $NAME";
			else
				source ./vm/$NAME.sh;
				disks=(${DISK[@]});
				if [[ $CDROM_OFF -eq 0 ]]; then
					disks+=(${CDROM[@]});
				fi
				for disk in "${disks[@]}"; do
					if [ ! -r "$disk" ] && [[ "$disk" =~ '/media/' ]]; then
						$RUN mount "$disk" || exit 1;
					fi
				done
				if ([[ "${DISK[@]}" =~ '/dev/' ]] || [ ! -z "$PCI" ]) && [ $(id -u) -ne 0 ]; then
					$SUDO DEBUG=$DEBUG $RUN ${ARGS[@]};
				else
					echo "[START] VM name: $NAME";
					if [ -z "$DEBUG" ]; then
						# TODO: придумать как screen заставить работать если завершается родительский процесс
						# nohup ./vm/$NAME.sh &> ./logs/$NAME.log &
						# screen -dmS easyQEMU_$NAME bash -c "DISPLAY=$DISPLAY ./vm/$NAME.sh 2>&1 | tee ./logs/$NAME.log";
						# screen -dmS easyQEMU_$NAME -L -Logfile ./logs/screen_$NAME.log -p 0 ./vm/$NAME.sh;
						echo "DISPLAY=$DISPLAY ./vm/$NAME.sh 2>&1 | tee ./logs/$NAME.log" | at now
					else
						./vm/$NAME.sh;
					fi
				fi
			fi
		fi
		exit;
	;;
	stop )
		[ ! -z "${ARGS[1]}" ] && NAME="$(basename ${ARGS[1]%.*})";
		if [ -z "$NAME" ]; then
			echo '[ERROR] Empty name vm';
		else
			if [ ! -r "./vm/$NAME.sh" ]; then
				echo "[ERROR] Not found vm: $NAME";
			else
				source ./vm/$NAME.sh;
				if ([[ "${DISK[@]}" =~ '/dev/' ]] || [ ! -z "$PCI" ]) && [ $(id -u) -ne 0 ]; then
					$SUDO $RUN ${ARGS[@]};
				else
					echo "[STOP] VM name: $NAME";
					fpid="${TMPDIR:-/tmp}/qemu_$NAME.pid";
					if [ -f "$fpid" ]; then
						pid=$(cat "$fpid");
						if [ ! -z "$pid" ] && [ -d "/proc/$pid" ]; then
							ppid=$(cat "/proc/$pid/status" | grep PPid: | grep -o "[0-9]*");
							echo "[STOP] pid: $pid, ppid: $ppid";
							# echo "quit" | nc -N 127.0.0.1 5555; # echo "quit" | nc -N 127.0.0.1 5$ppid;
							# А надо ли? Если процесс можно просто убить...
							# if [ -d "/proc/$pid" ]; then
								# sleep 1;
								# if [ -d "/proc/$pid" ]; then
									echo "[KILL]";
									kill $pid;
								# fi
							# fi
						fi
					fi
				fi
			fi
		fi
		exit;
	;;
esac

if test -n "$STY"; then
	echo "This is a screen session named '$STY'";
else
	echo "This is NOT a screen session.";
fi

echo "[DEBUG] NAME: $NAME";
echo "[DEBUG] TERM: $TERM";
echo "[DEBUG] STY: $STY";
echo "[DEBUG] DISPLAY: $DISPLAY";
echo "[DEBUG] USER: $USER";
echo "[DEBUG] SUDO_USER: $SUDO_USER";
echo "[DEBUG] PWD: $(pwd)";
echo "[DEBUG] ARCH: $(uname -m)";

[ -z "$VIRTIO" ] && VIRTIO=1;
[ -z "$UEFI" ] && UEFI=1;
[ -z "$CDROM_OFF" ] && CDROM_OFF=0;
[ -z "$VNC_PORT" ] && VNC_PORT=;
[ -z "$HEADLESS" ] && HEADLESS=0;
[ -z "$DISK_SIZE" ] && DISK_SIZE="20G";
[ -z "$HOSTFWD" ] && {
	# TODO:
	# hostfwd=tcp::12345-:22
	# guestfwd=tcp:10.0.2.100:49999-tcp:127.0.0.1:49999
	# -redir tcp:12345::22
	HOSTFWD=;
}
[ -z "$CPUS" ] && CPUS=$(nproc);
[ -z "$ARCH" ] && ARCH=$(uname -m); # (uname -m = x86_64) и (uname -p = x86_64) и (uname -i = x86_64)
if [ -z "$RAM" ]; then
	RAM=$(awk '/MemFree/ { printf "%d", $2/1024 }' /proc/meminfo);
	if [[ "$RAM" -lt '2048' ]]; then
		RAM=$(awk '/MemAvailable/ { printf "%d", $2/1024-1024 }' /proc/meminfo);
		if [[ "$RAM" -lt '128' ]]; then
			RAM='128';
		fi
	fi
fi

display_managers=("sddm" "gdm" "lightdm" "lxdm" "xdm" "mdm" "display-manager");
vtconsoles=();
drivers=();
vendors=();
devices=();
video=(); # ID, DRIVER, NAME, ROM
vga=();
qemu=(${ARGS[@]});

if [ ! -z "$NAME" ]; then
	qemu+=(
		# -monitor telnet:127.0.0.1:5555,server,nowait # -monitor telnet:127.0.0.1:5$$,server,nowait
		-pidfile ${TMPDIR:-/tmp}/qemu_$NAME.pid
	);
fi

qemu+=(
	-enable-kvm
	-m $RAM
	-smp $CPUS
	-machine type=q35,accel=kvm
	# -cpu host,migratable=on,hv-time,hv-relaxed,hv-vapic,hv-spinlocks=0x1fff
	# -cpu host,hv-relaxed,hv-vapic,hv-spinlocks=0x1fff # hv-time off
	-cpu host,smep=off,hv-relaxed,hv-vapic,hv-spinlocks=0x1fff
	# -cpu host,smep=off,hypervisor=off,hv-relaxed,hv-vapic,hv-spinlocks=0x1fff # hypervisor off
	-smbios type=2
	# -rtc base=localtime # а надо ли?
	# -global isa-fdc.fdtypeA=none # впринципе в nodefaults уже есть... или всё же оставить...
	-global kvm-pit.lost_tick_policy=delay
	-global ICH9-LPC.disable_s3=1
	-global ICH9-LPC.disable_s4=1
	-msg timestamp=on
	-no-user-config
	-nodefaults
	# -no-hpet
	-boot strict=on
	-k en-us
);
if [ -z "$DISPLAY" ] || [ $HEADLESS -eq 1 ]; then
	[ -z "$VNC_PORT" ] && {
		VNC_PORT=1;
	}
	vga=(-display none);
else
	vga=(
		-usb
		-device usb-kbd
		-device usb-tablet
		-device ich9-intel-hda
		-device hda-output
	);
fi
vga+=(-vga qxl);
if [ ! -z "$VNC_PORT" ]; then
	qemu+=(-vnc :$VNC_PORT);
fi
hostfwds="";
if [ ! -z "$HOSTFWD" ]; then
	for fwd in "${HOSTFWD[@]}"; do
		hostfwds+=",hostfwd=$fwd";
	done
fi
# TODO: добавить поддержку smb
qemu+=(
	-netdev user,id=hostnet0$hostfwds
);
if [ ! -z "$PCI" ]; then
	qemu+=(
		-device pcie-root-port,port=0x10,chassis=1,id=pci.1,bus=pcie.0,multifunction=on,addr=0x2
		-device e1000-82545em,netdev=hostnet0,id=net0,mac=52:54:00:0e:0d:20,bus=pci.1,addr=0x0
	);
else
	qemu+=(
		-device e1000-82545em,netdev=hostnet0,id=net0,mac=52:54:00:0e:0d:20
	);
fi
for disk_img in "${DISK[@]}"; do
	if [ ${disk_img##*.} == "vhd" ]; then
		disk_format='vpc';
	else
		disk_format='raw';
	fi
	if [ ! -r "$disk_img" ] && [[ "$disk_img" =~ '/media/' ]]; then
		$RUN mount "$disk_img" || exit 1;
	fi
	if [ ! -r "$disk_img" ]; then
		if [[ "$disk_img" =~ '/dev/' ]]; then
			echo "[ERROR] Not found disk: $disk_img" && exit 1;
		fi
		echo "[CREATE DRIVE] $disk_format: $disk_img ($DISK_SIZE)";
		qemu-img create -f $disk_format $disk_img $DISK_SIZE || exit 1
	fi
	if [ $VIRTIO -eq 1 ]; then
		qemu+=(
			-drive file=$disk_img,format=$disk_format,media=disk,if=virtio,cache=writeback
		);
	else
		qemu+=(
			-drive file=$disk_img,format=$disk_format,media=disk
		);
	fi
done
if [ $CDROM_OFF -eq 0 ]; then
	for disk_iso in "${CDROM[@]}"; do
		if [ ! -r "$disk_iso" ] && [[ "$disk_iso" =~ '/media/' ]]; then
			$RUN mount "$disk_iso" || exit 1;
		fi
		if [ ! -r "$disk_iso" ]; then
			echo "[ERROR] Not found disk: $disk_iso" && exit 1;
		fi
		qemu+=(-drive file=$disk_iso,media=cdrom);
	done
	if [ ! -z "$DISK" ]; then
		if [ ${DISK[0]##*.} == "vhd" ]; then
			driver="./tools/virtio-win-0.1.215.iso";
		else
			driver="./tools/vtoyboot-1.0.20.iso";
		fi
		if [ -r "$driver" ]; then
			qemu+=(-drive file=$driver,media=cdrom);
		fi
	fi
fi
if [ $UEFI -eq 1 ]; then
	qemu+=(-bios /usr/share/ovmf/OVMF.fd);
fi

if [ ! -z "$PCI" ]; then
	if [ $(id -u) -ne 0 ]; then
		echo "[ERROR] access denied";
	fi
	for i in "${!PCI[@]}"; do
		dev="0000:${PCI[$i]}";
		# driver=$(readlink /sys/bus/pci/devices/$dev/driver/module);
		driver=$(readlink /sys/bus/pci/devices/$dev/driver);
		if [ $driver ]; then
			driver=$(basename $driver);
		fi
		# [[ " ${drivers[@]} " =~ " amdgpu " ]] || [[ " ${drivers[@]} " =~ " nvidea " ]] || [[ " ${drivers[@]} " =~ " nuveau " ]]
		if [ "$driver" == "amdgpu" ] || [ "$driver" == "nvidea" ] || [ "$driver" == "nuveau" ]; then
			video_name=$(DISPLAY=:0 xrandr --listproviders | grep "pci:$dev" | sed 's/.*name://g' | sed 's/ @.*//g' | sed 's/ /_/g');
			if [ -z "$video_name" ]; then
				video_name="$driver";
			fi
			# TODO: если уровнем выше нет директории bios, то использовать директорию bios в текущей директории
			video_rom="../bios/$video_name.rom";
			video=(
				$dev
				$driver
				$video_name
				$video_rom
			);
		fi
		drivers[$i]=$driver;
	done
	if [ ! -z "$video" ]; then
		vga=(-vga none -display none);
		if [ "${video[1]}" == "amdgpu" ]; then
			if [ ! -r "${video[3]}" ]; then
				echo "[RUN] amdvbflash, dump video_rom: ${video[3]}";
				./tools/amdvbflash -s 0 "${video[3]}" || exit 1;
			fi
		fi
		for i in "${!display_managers[@]}"; do
			dm="${display_managers[$i]}";
			unlink=1;
			if [ ! -z $(type -p systemctl) ]; then
				if systemctl is-active --quiet "$dm.service"; then
					echo "[STOP] dm: $dm, supervisor: systemd";
					unlink=0;
					systemctl stop "$dm.service";
					while systemctl is-active --quiet "$dm.service"; do
						sleep 1;
					done
				fi
			fi
			if [ ! -z $(type -p sv) ]; then
				if sv status $dm; then
					echo "[STOP] dm: $dm, supervisor: runit";
					unlink=0;
					sv stop $dm;
				fi
			fi
			if [ $unlink -eq 1 ]; then
				unset -v display_managers[$i];
			fi
		done
		for (( i = 0; i < 16; i++)); do
			if [ -e /sys/class/vtconsole/vtcon$i ]; then
				if [ $(cat /sys/class/vtconsole/vtcon$i/name | grep -c "frame buffer") = 1 ]; then
					echo "[STOP] console: $i";
					vtconsoles+=($i);
					echo 0 > /sys/class/vtconsole/vtcon$i/bind;
				fi
			fi
		done
		# [[ " ${drivers[@]} " =~ " nvidea " ]] &&
		if [ "${video[1]}" == "nvidea" ]; then
			echo "[STOP] nvidea efi-framebuffer";
			echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind;
		fi
	fi
	modprobe vfio-pci;
	for i in "${!PCI[@]}"; do
		ii=$((i+1))
		iii=$((ii+1))
		dev="0000:${PCI[$i]}";
		vendor=$(cat /sys/bus/pci/devices/$dev/vendor);
		device=$(cat /sys/bus/pci/devices/$dev/device);
		driver="${drivers[$i]}";
		drivers[$i]=$driver;
		vendors[$i]=$vendor;
		romfile='';
		if [ "$driver" == "amdgpu" ]; then
			romfile=",romfile=${video[3]}";
		fi
		qemu+=(-device pcie-root-port,port=0x1$ii,chassis=$iii,id=pci.$iii,bus=pcie.0,addr=0x2.0x$ii);
		qemu+=(-device vfio-pci,host=$dev,id=hostdev$i,bus=pci.$iii,addr=0x0$romfile);
		echo "[STOP] dev: $dev, vendor: $vendor, device: $device, driver: $driver";
		if [ -e /sys/bus/pci/devices/$dev/driver ]; then
			echo $dev > /sys/bus/pci/devices/$dev/driver/unbind;
		fi
		echo $vendor $device > /sys/bus/pci/drivers/vfio-pci/new_id;
		echo $dev > /sys/bus/pci/drivers/vfio-pci/bind;
	done
fi

qemu+=(${vga[@]});

echo "[START] qemu";
echo "qemu-system-$ARCH ${qemu[@]}";
qemu-system-$ARCH "${qemu[@]}";
echo "[STOP] qemu";

if [ ! -z "$PCI" ]; then
	for i in "${!PCI[@]}"; do
		dev="0000:${PCI[$i]}";
		vendor="${vendors[$i]}";
		device="${devices[$i]}";
		driver="${drivers[$i]}";
		echo "[START] dev: $dev, vendor: $vendor, device: $device, driver: $driver";
		echo $dev > /sys/bus/pci/drivers/vfio-pci/unbind;
		echo $vendor $device > /sys/bus/pci/drivers/vfio-pci/remove_id;
		if [ -e /sys/bus/pci/drivers/$driver/bind ]; then
			echo $dev > /sys/bus/pci/drivers/$driver/bind;
		fi
		# echo 1 > /sys/bus/pci/devices/0000:03:00.0/remove
		# echo 1 > /sys/bus/pci/devices/0000:03:00.1/remove
		# echo 1 > /sys/bus/pci/rescan
	done
	if [ ! -z "$video" ]; then
		for dm in "${display_managers[@]}"; do
			if [ ! -z $(type -p systemctl) ]; then
				echo "[START] dm: $dm, supervisor: systemd";
				systemctl start "$dm.service";
			fi
			if [ ! -z $(type -p sv) ]; then
				echo "[START] dm: $dm, supervisor: runit";
				sv start $dm;
			fi
		done
		for i in "${vtconsoles[@]}"; do
			if [ -e /sys/class/vtconsole/vtcon$i ]; then
				if [ $(cat /sys/class/vtconsole/vtcon$i/name | grep -c "frame buffer") = 1 ]; then
					echo "[START] console: $i";
					echo 1 > /sys/class/vtconsole/vtcon$i/bind;
				fi
			fi
		done
		if [ "${video[1]}" == "nvidea" ]; then
			echo "[START] nvidea efi-framebuffer";
			echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/bind;
		fi
	fi
fi
