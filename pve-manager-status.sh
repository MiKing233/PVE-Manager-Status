#!/bin/bash
# pve-manager-status.sh
# Last Modified: 2025-10-05

echo -e "\n🛠️ \033[1;33;41mPVE-Manager-Status v0.4.8 by MiKing233\033[0m"

echo -e "为你的 ProxmoxVE 节点概要页面添加扩展的硬件监控信息"
echo -e "OpenSource on GitHub (https://github.com/MiKing233/PVE-Manager-Status)\n"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "⛔ 请以 root 身份运行此脚本!\n"
    exit 1
fi

read -p "确认执行吗? [y/N]:" para

# 脚本执行前确认
[[ "$para" =~ ^[Yy]$ ]] || { [[ "$para" =~ ^[Nn]$ ]] && echo -e "\n🚫 操作取消, 未执行任何操作!" && exit 0; echo -e "\n⚠️ 无效输入, 未执行任何操作!"; exit 1; }

nodes="/usr/share/perl5/PVE/API2/Nodes.pm"
pvemanagerlib="/usr/share/pve-manager/js/pvemanagerlib.js"
pvever=$(pveversion | awk -F"/" '{print $2}')

echo -e "\n⚙️ 当前 Proxmox VE 版本: $pvever"



####################   备份步骤   ####################

echo -e "\n💾 修改开始前备份原文件:"

delete_old_backups() {
    local pattern="$1"
    local description="$2"

    shopt -s nullglob
    local files=($pattern)
    shopt -u nullglob

    if [ ${#files[@]} -gt 0 ]; then
        for file in "${files[@]}"; do
            echo "旧备份清理: $file ♻️"
        done
        rm -f "${files[@]}"
    else
        echo "没有发现任何旧备份文件! ♻️"
    fi
}
echo -e "清理旧的备份文件..."
delete_old_backups "${nodes}.*.bak" "nodes"
delete_old_backups "${pvemanagerlib}.*.bak" "pvemanagerlib"

echo -e "备份当前将要被修改的文件..."
cp "$nodes" "${nodes}.${pvever}.bak"
echo "新备份生成: ${nodes}.${pvever}.bak ✅"
cp "$pvemanagerlib" "${pvemanagerlib}.${pvever}.bak"
echo "新备份生成: ${pvemanagerlib}.${pvever}.bak ✅"



####################   依赖检查 & 环境准备   ####################

# 避免重复修改, 重装 pve-manager
echo -e "\n♻️ 避免重复修改, 重新安装 pve-manager..."
apt-get install --reinstall -y pve-manager

# 软件包依赖
echo -e "\n🗃️ 检查依赖软件包安装情况..."
packages=(sysstat lm-sensors smartmontools)
missing=()

# 检查依赖状态
installed_list=$(apt list --installed 2>/dev/null)
for pkg in "${packages[@]}"; do
    if echo "$installed_list" | grep -q "^$pkg/"; then
        echo "$pkg: 已安装✅"
    else
        echo "$pkg: 未安装⛔"
        missing+=("$pkg")
    fi
done

# 安装缺失的包
if [ ${#missing[@]} -ne 0 ]; then
    echo -e "\n📦 检查到软件包缺失: ${missing[*]} 开始安装..."
    apt-get update && apt-get install -y "${missing[@]}"
else
    echo -e "所有依赖软件包均已安装!"
fi

# 配置传感器模块
echo -e "\n🧰 开始配置传感器模块..."
sensors-detect --auto > /tmp/sensors

drivers=$(sed -n '/Chip drivers/,/\#----cut here/p' /tmp/sensors | sed '/Chip /d;/cut/d')

if [ -n "$drivers" ]; then
    echo "发现传感器模块, 正在配置以便开机自动加载"
    for drv in $drivers; do
        modprobe "$drv"
        if grep -qx "$drv" /etc/modules; then
            echo "模块 $drv 已存在于 /etc/modules ➡️"
        else
            echo "$drv" >> /etc/modules
            echo "模块 $drv 已添加至 /etc/modules ✅"
        fi
    done
    if [[ -e /etc/init.d/kmod ]]; then
        echo "正在应用模块配置使其立即生效..."
        /etc/init.d/kmod start &>/dev/null
        echo "模块配置已生效 ✅"
    else
        echo "未找到 /etc/init.d/kmod 跳过此步骤 ➡️"
    fi
    echo "传感器模块已配置完成!"
elif grep -q "No modules to load, skipping modules configuration" /tmp/sensors; then
    echo "未找到需要手动加载的模块, 跳过配置步骤 (可能已由内核自动加载) ➡️"
elif grep -q "Sorry, no sensors were detected" /tmp/sensors; then
    echo "未检测到任何传感器, 跳过配置步骤 (当前环境可能为虚拟机) ⚠️"
else
    echo "发生预期外的错误, 跳过配置步骤! 你的设备可能不支持或内核未包含相关模块 ⛔"
fi

rm -f /tmp/sensors

# 配置必要的执行权限 (优化版替代危险的 chmod +s)
echo -e "\n🔩 配置必要的执行权限..."
echo -e "允许 www-data 用户以 sudo 权限执行部分监控命令"
SUDOERS_FILE="/etc/sudoers.d/pve-manager-status"
# 首先移除可能被添加的 SUID 权限设置, 以防曾经运行过其它监控脚本
binaries=(/usr/sbin/nvme /usr/bin/iostat /usr/bin/sensors /usr/bin/cpupower /usr/sbin/smartctl /usr/sbin/turbostat)
for bin in "${binaries[@]}"; do
    if [[ -e $bin && -u $bin ]]; then
        chmod -s "$bin" && echo "检测到不安全的 SUID 权限已移除: $bin ⚠️"
    fi
done

# 定义需要 sudo 权限执行命令的绝对路径
IOSTAT_PATH=$(command -v iostat)
SENSORS_PATH=$(command -v sensors)
SMARTCTL_PATH=$(command -v smartctl)
TURBOSTAT_PATH=$(command -v turbostat)

# 配置 sudoers 规则内容
echo -e "正在配置 sudoers 规则内容并进行语法检查..."
read -r -d '' SUDOERS_CONTENT << EOM
# Allow www-data user (PVE Web GUI) to run specific hardware monitoring commands
# This file is managed by pve-manager-status.sh (https://github.com/MiKing233/PVE-Manager-Status)

www-data ALL=(root) NOPASSWD: ${SENSORS_PATH}
www-data ALL=(root) NOPASSWD: ${SMARTCTL_PATH} -a /dev/*
www-data ALL=(root) NOPASSWD: ${IOSTAT_PATH} -d -x -k 1 1
www-data ALL=(root) NOPASSWD: ${TURBOSTAT_PATH} -S -q -s PkgWatt -i 0.1 -n 1 -c package
EOM

# 使用 visudo 在最终添加前对 sudoers 规则执行语法检查
TMP_SUDOERS=$(mktemp)
echo "${SUDOERS_CONTENT}" > "${TMP_SUDOERS}"

if visudo -c -f "${TMP_SUDOERS}" &> /dev/null; then
    echo "sudoers 规则语法检查通过 ✅"
    mv "${TMP_SUDOERS}" "${SUDOERS_FILE}"
    chown root:root "${SUDOERS_FILE}"
    chmod 0440 "${SUDOERS_FILE}"
    echo "已成功配置 sudo 规则于: ${SUDOERS_FILE} 🔐"
else
    echo "sudoers 规则语法错误, 操作终止! ⛔"
    rm -f "${TMP_SUDOERS}"
    exit 1
fi

# 确保 msr 模块被加载并设为开机自启，为 turbostat 提供支持
modprobe msr && echo msr > /etc/modules-load.d/turbostat-msr.conf



echo -e "\n📝 开始执行修改..."

####################   修改node.pm   ####################

tmpf1=$(mktemp /tmp/pve-manager-status.XXXXXX) || exit 1
cat > "$tmpf1" << 'EOF'

        my $cpumodes = `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`;
        my $cpupowers = `sudo turbostat -S -q -s PkgWatt -i 0.1 -n 1 -c package | grep -v PkgWatt`;
        $res->{cpupower} = $cpumodes . $cpupowers;

        my $cpufreqs = `lscpu | grep MHz`;
        my $threadfreqs = `cat /proc/cpuinfo | grep -i "cpu MHz"`;
        $res->{cpufreq} = $cpufreqs . $threadfreqs;

        $res->{sensors} = `sudo sensors`;

        my $nvme0_info = `sudo smartctl -a /dev/nvme0 | grep -E "Model Number|(?=Total|Namespace)[^:]+Capacity|Temperature:|Available Spare:|Percentage|Data Unit|Power Cycles|Power On Hours|Unsafe Shutdowns|Integrity Errors"`;
        my $nvme0_io = `sudo iostat -d -x -k 1 1 | grep -E "^nvme0"`;
        $res->{nvme0_status} = $nvme0_info . $nvme0_io;

        $res->{sata_status} = `sudo smartctl -a /dev/sd? | grep -E "Device Model|Capacity|Power_On_Hours|Temperature"`;
EOF

echo "正在修改: $nodes..."
sed -i '/PVE::pvecfg::version_text/ r '"$tmpf1"'' "$nodes"
rm -f "$tmpf1"



####################   修改pvemanagerlib.js   ####################

tmpf2=$(mktemp /tmp/pve-manager-status.XXXXXX) || exit 1
cat > "$tmpf2" << 'EOF'
        {
            itemId: 'cpupower',
            colspan: 2,
            printBar: false,
            title: gettext('CPU能耗'),
            textField: 'cpupower',
            renderer:function(value){
                function colorizeCpuMode(mode) {
                    if (mode === 'powersave') return `<span style="color:green; font-weight:bold;">${mode}</span>`;
                    if (mode === 'performance') return `<span style="color:red; font-weight:bold;">${mode}</span>`;
                    return `<span style="color:orange; font-weight:bold;">${mode}</span>`;
                }
                function colorizeCpuPower(power) {
                    const powerNum = parseFloat(power);
                    if (powerNum < 20) return `<span style="color:green; font-weight:bold;">${power} W</span>`;
                    if (powerNum < 50) return `<span style="color:orange; font-weight:bold;">${power} W</span>`;
                    return `<span style="color:red; font-weight:bold;">${power} W</span>`;
                }
                const w0 = value.split('\n')[0].split(' ')[0];
                const w1 = value.split('\n')[1].split(' ')[0];
                return `CPU电源模式: ${colorizeCpuMode(w0)} | CPU功耗: ${colorizeCpuPower(w1)}`
            }
        },
        {
            itemId: 'cpufreq',
            colspan: 2,
            printBar: false,
            title: gettext('CPU频率'),
            textField: 'cpufreq',
            renderer:function(value){
                function colorizeCpuFreq(freq) {
                    const freqNum = parseFloat(freq);
                    if (freqNum < 1500) return `<span style="color:green; font-weight:bold;">${freq} MHz</span>`;
                    if (freqNum < 3000) return `<span style="color:orange; font-weight:bold;">${freq} MHz</span>`;
                    return `<span style="color:red; font-weight:bold;">${freq} MHz</span>`;
                }
                const f0 = value.match(/cpu MHz.*?([\d]+)/)[1];
                const f1 = value.match(/CPU min MHz.*?([\d]+)/)[1];
                const f2 = value.match(/CPU max MHz.*?([\d]+)/)[1];
                return `CPU实时: ${colorizeCpuFreq(f0)} | 最小: ${f1} MHz | 最大: ${f2} MHz `
            }
        },
        {
            itemId: 'sensors',
            colspan: 2,
            printBar: false,
            title: gettext('传感器'),
            textField: 'sensors',
            renderer: function(value) {
                function colorizeCpuTemp(temp) {
                    const tempNum = parseFloat(temp);
                    if (tempNum < 60) return `<span style="color:green; font-weight:bold;">${temp}°C</span>`;
                    if (tempNum < 80) return `<span style="color:orange; font-weight:bold;">${temp}°C</span>`;
                    return `<span style="color:red; font-weight:bold;">${temp}°C</span>`;
                }
                function colorizeGpuTemp(temp) {
                    const tempNum = parseFloat(temp);
                    if (tempNum < 60) return `<span style="color:green; font-weight:bold;">${temp}°C</span>`;
                    if (tempNum < 80) return `<span style="color:orange; font-weight:bold;">${temp}°C</span>`;
                    return `<span style="color:red; font-weight:bold;">${temp}°C</span>`;
                }
                function colorizeAcpiTemp(temp) {
                    const tempNum = parseFloat(temp);
                    if (tempNum < 60) return `<span style="color:green; font-weight:bold;">${temp}°C</span>`;
                    if (tempNum < 80) return `<span style="color:orange; font-weight:bold;">${temp}°C</span>`;
                    return `<span style="color:red; font-weight:bold;">${temp}°C</span>`;
                }
                function colorizeFanRpm(rpm) {
                    const rpmNum = parseFloat(rpm);
                    if (rpmNum < 1500) return `<span style="color:green; font-weight:bold;">${rpm}转/分钟</span>`;
                    if (rpmNum < 3000) return `<span style="color:orange; font-weight:bold;">${rpm}转/分钟</span>`;
                    return `<span style="color:red; font-weight:bold;">${rpm}转/分钟</span>`;
                }
                value = value.replace(/Â/g, '');
                let data = [];
                let cpus = value.matchAll(/^(?:coretemp-isa|k10temp-pci)-(\w{4})$\n.*?\n((?:Package|Core|Tctl)[\s\S]*?^\n)+/gm);
                for (const cpu of cpus) {
                    let cpuNumber = parseInt(cpu[1], 10);
                    data[cpuNumber] = {
                        packages: [],
                        cores: []
                    };

                    let packages = cpu[2].matchAll(/^(?:Package id \d+|Tctl):\s*\+([^°C ]+).*$/gm);
                    for (const package of packages) {
                        data[cpuNumber]['packages'].push(package[1]);
                    }
                    let cores = cpu[2].matchAll(/^Core (\d+):\s*\+([^°C ]+).*$/gm);
                    for (const core of cores) {
                        var corecombi = `核心 ${core[1]}: ${colorizeCpuTemp(core[2])}`
                        data[cpuNumber]['cores'].push(corecombi);
                    }
                }

                let output = '';
                for (const [i, cpu] of data.entries()) {
                    if (cpu.packages.length > 0) {
                        for (const packageTemp of cpu.packages) {
                            output += `CPU ${i}: ${colorizeCpuTemp(packageTemp)} | `;
                        }
                    }

                    let gpus = value.matchAll(/^amdgpu-pci-(\w*)$\n((?!edge:)[ \S]*?\n)*((?:edge)[\s\S]*?^\n)+/gm);
                    for (const gpu of gpus) {
                        let gpuNumber = 0;
                        data[gpuNumber] = {
                            edges: []
                        };

                        let edges = gpu[3].matchAll(/^edge:\s*\+([^°C ]+).*$/gm);
                        for (const edge of edges) {
                            data[gpuNumber]['edges'].push(edge[1]);
                        }

                        for (const [k, gpu] of data.entries()) {
                            if (gpu.edges.length > 0) {
                                output += '核显: ';
                                for (const edgeTemp of gpu.edges) {
                                    output += `${colorizeGpuTemp(edgeTemp)}, `;
                                }
                                output = output.slice(0, -2);
                                output += ' | ';
                            } else {
                                output = output.slice(0, -2);
                            }
                        }
                    }

                    let acpitzs = value.matchAll(/^acpitz-acpi-(\d*)$\n.*?\n((?:temp)[\s\S]*?^\n)+/gm);
                    for (const acpitz of acpitzs) {
                        let acpitzNumber = parseInt(acpitz[1], 10);
                        data[acpitzNumber] = {
                            acpisensors: []
                        };

                        let acpisensors = acpitz[2].matchAll(/^temp\d+:\s*\+([^°C ]+).*$/gm);
                        for (const acpisensor of acpisensors) {
                            data[acpitzNumber]['acpisensors'].push(acpisensor[1]);
                        }

                        for (const [k, acpitz] of data.entries()) {
                            if (acpitz.acpisensors.length > 0) {
                                output += '主板: ';
                                for (const acpiTemp of acpitz.acpisensors) {
                                    output += `${colorizeAcpiTemp(acpiTemp)}, `;
                                }
                                output = output.slice(0, -2);
                                output += ' | ';
                            } else {
                                output = output.slice(0, -2);
                            }
                        }
                    }

                    let FunStates = value.matchAll(/^(?:[a-zA-z]{2,3}\d{4}|dell_smm)-isa-(\w{4})$\n((?![ \S]+: *\d+ +RPM)[ \S]*?\n)*((?:[ \S]+: *\d+ RPM)[\s\S]*?^\n)+/gm);
                    for (const FunState of FunStates) {
                        let FanNumber = 0;
                        data[FanNumber] = {
                            rotationals: [],
                            cpufans: [],
                            motherboardfans: [],
                            pumpfans: [],
                            systemfans: []
                        };

                        let rotationals = FunState[3].match(/^([ \S]+: *[0-9]\d* +RPM)[ \S]*?$/gm);
                        for (const rotational of rotationals) {
                            if (rotational.toLowerCase().indexOf("pump") !== -1 || rotational.toLowerCase().indexOf("opt") !== -1){
                                let pumpfans = rotational.matchAll(/^[ \S]+: *([1-9]\d*) +RPM[ \S]*?$/gm);
                                for (const pumpfan of pumpfans) {
                                    data[FanNumber]['pumpfans'].push(pumpfan[1]);
                                }
                            } else if (rotational.toLowerCase().indexOf("cpu") !== -1 || rotational.toLowerCase().indexOf("processor") !== -1){
                                let cpufans = rotational.matchAll(/^[ \S]+: *([1-9]\d*) +RPM[ \S]*?$/gm);
                                for (const cpufan of cpufans) {
                                    data[FanNumber]['cpufans'].push(cpufan[1]);
                                }
                            } else if (rotational.toLowerCase().indexOf("motherboard") !== -1){
                                let motherboardfans = rotational.matchAll(/^[ \S]+: *([1-9]\d*) +RPM[ \S]*?$/gm);
                                for (const motherboardfan of motherboardfans) {
                                    data[FanNumber]['motherboardfans'].push(motherboardfan[1]);
                                }
                            }  else {
                                let systemfans = rotational.matchAll(/^[ \S]+: *([1-9]\d*) +RPM[ \S]*?$/gm);
                                for (const systemfan of systemfans) {
                                    data[FanNumber]['systemfans'].push(systemfan[1]);
                                }
                            }
                        }

                        for (const [j, FunState] of data.entries()) {
                            if (FunState.cpufans.length > 0 || FunState.motherboardfans.length > 0 || FunState.pumpfans.length > 0 || FunState.systemfans.length > 0) {
                                output += '风扇: ';
                                if (FunState.cpufans.length > 0) {
                                    output += 'CPU-';
                                    for (const cpufan_value of FunState.cpufans) {
                                        output += `${colorizeFanRpm(cpufan_value)}, `;
                                    }
                                }

                                if (FunState.motherboardfans.length > 0) {
                                    output += '主板-';
                                    for (const motherboardfan_value of FunState.motherboardfans) {
                                        output += `${colorizeFanRpm(motherboardfan_value)}, `;
                                    }
                                }

                                if (FunState.pumpfans.length > 0) {
                                    output += '水冷-';
                                    for (const pumpfan_value of FunState.pumpfans) {
                                        output += `${colorizeFanRpm(pumpfan_value)}, `;
                                    }
                                }

                                if (FunState.systemfans.length > 0) {
                                    if (FunState.cpufans.length > 0 || FunState.pumpfans.length > 0) {
                                        output += '系统-';
                                    }
                                    for (const systemfan_value of FunState.systemfans) {
                                        output += `${colorizeFanRpm(systemfan_value)}, `;
                                    }
                                }
                                output = output.slice(0, -2);
                                output += ' | ';
                            } else if (FunState.cpufans.length == 0 && FunState.pumpfans.length == 0 && FunState.systemfans.length == 0) {
                                output += ' 风扇: 停转';
                                output += ' | ';
                            } else {
                                output = output.slice(0, -2);
                            }
                        }
                    }
                    output = output.slice(0, -2);

                    if (cpu.cores.length > 1) {
                        output += '\n';
                        for (j = 1;j < cpu.cores.length;) {
                            for (const coreTemp of cpu.cores) {
                                output += `${coreTemp} | `;
                                j++;
                                if ((j-1) % 4 == 0){
                                    output = output.slice(0, -2);
                                    output += '\n';
                                }
                            }
                        }
                        output = output.slice(0, -2);
                    }
                    output += '\n';
                }

                output = output.slice(0, -2);
                return output.replace(/\n/g, '<br>');
            }
        },
        {
            itemId: 'corefreq',
            colspan: 2,
            printBar: false,
            title: gettext('核心频率'),
            textField: 'cpufreq',
            renderer: function(value) {
                function colorizeCpuFreq(freq) {
                    const freqNum = parseFloat(freq);
                    if (freqNum < 1500) return `<span style="color:green; font-weight:bold;">${freq} MHz</span>`;
                    if (freqNum < 3000) return `<span style="color:orange; font-weight:bold;">${freq} MHz</span>`;
                    return `<span style="color:red; font-weight:bold;">${freq} MHz</span>`;
                }
                const freqMatches = value.matchAll(/^cpu MHz\s*:\s*([\d\.]+)/gm);
                const frequencies = [];

                for (const match of freqMatches) {
                    const coreNum = frequencies.length + 1;
                    frequencies.push(`线程 ${coreNum}: ${colorizeCpuFreq(parseInt(match[1]))}`);
                }

                if (frequencies.length === 0) {
                    return '无法获取CPU频率信息';
                }

                const groupedFreqs = [];
                for (let i = 0; i < frequencies.length; i += 4) {
                    const group = frequencies.slice(i, i + 4);
                    groupedFreqs.push(group.join(' | '));
                }

                return groupedFreqs.join('<br>');
            }
        },
        {
            itemId: 'nvme0-status',
            colspan: 2,
            printBar: false,
            title: gettext('NVMe硬盘'),
            textField: 'nvme0_status',
            renderer:function(value){
                function getSsdLifeColor(life) {
                    const lifeNum = parseFloat(life);
                    if (lifeNum < 50) return 'red';
                    if (lifeNum < 80) return 'orange';
                    return 'green';
                }
                function colorizeSsdModel(model, life) {
                    const color = getSsdLifeColor(life);
                    return `<span style="color:${color}; font-weight:bold;">${model}</span>`;
                }
                function colorizeSsdLife(life) {
                    const color = getSsdLifeColor(life);
                    return `<span style="color:${color}; font-weight:bold;">${life}%</span>`;
                }
                function colorizeSsdTemp(temp) {
                    const tempNum = parseFloat(temp);
                    if (tempNum < 50) return `<span style="color:green; font-weight:bold;">${temp}°C</span>`;
                    if (tempNum < 70) return `<span style="color:orange; font-weight:bold;">${temp}°C</span>`;
                    return `<span style="color:red; font-weight:bold;">${temp}°C</span>`;
                }
                function colorizeSsdLoad(load) {
                    const loadNum = parseFloat(load);
                    if (loadNum < 50) return `<span style="color:green; font-weight:bold;">${load}%</span>`;
                    if (loadNum < 80) return `<span style="color:orange; font-weight:bold;">${load}%</span>`;
                    return `<span style="color:red; font-weight:bold;">${load}%</span>`;
                }
                function colorizeIoSpeed(speed) {
                    const speedNum = parseFloat(speed);
                    if (speedNum > 1000) return `<span style="color:red; font-weight:bold;">${speed}MB/s</span>`;
                    if (speedNum < 100) return `<span style="color:green; font-weight:bold;">${speed}MB/s</span>`;
                    return `<span style="color:orange; font-weight:bold;">${speed}MB/s</span>`;
                }
                function colorizeIoLatency(latency) {
                    const latencyNum = parseFloat(latency);
                    if (latencyNum > 10) return `<span style="color:red; font-weight:bold;">${latency}ms</span>`;
                    if (latencyNum < 1) return `<span style="color:green; font-weight:bold;">${latency}ms</span>`;
                    return `<span style="color:orange; font-weight:bold;">${latency}ms</span>`;
                }
                if (value.length > 0) {
                    value = value.replace(/Â/g, '');
                    let data = [];
                    let nvmeNumber = -1;

                    let nvmes = value.matchAll(/(^(?:Model|Total|Temperature:|Available Spare:|Percentage|Data|Power|Unsafe|Integrity Errors|nvme)[\s\S]*)+/gm);
                    
                    for (const nvme of nvmes) {
                        if (/Model Number:/.test(nvme[1])) {
                            nvmeNumber++; 
                            data[nvmeNumber] = {
                                Models: [],
                                Integrity_Errors: [],
                                Capacitys: [],
                                Temperatures: [],
                                Available_Spares: [],
                                Useds: [],
                                Reads: [],
                                Writtens: [],
                                Cycles: [],
                                Hours: [],
                                Shutdowns: [],
                                States: [],
                                r_kBs: [],
                                r_awaits: [],
                                w_kBs: [],
                                w_awaits: [],
                                utils: []
                            };
                        }

                        if (nvmeNumber === -1) continue;

                        let Models = nvme[1].matchAll(/^Model Number: *([ \S]*)$/gm);
                        for (const Model of Models) {
                            data[nvmeNumber]['Models'].push(Model[1]);
                        }

                        let Integrity_Errors = nvme[1].matchAll(/^Media and Data Integrity Errors: *([ \S]*)$/gm);
                        for (const Integrity_Error of Integrity_Errors) {
                            data[nvmeNumber]['Integrity_Errors'].push(Integrity_Error[1]);
                        }

                        let Capacitys = nvme[1].matchAll(/^(?=Total|Namespace)[^:]+Capacity:[^\[]*\[([ \S]*)\]$/gm);
                        for (const Capacity of Capacitys) {
                            data[nvmeNumber]['Capacitys'].push(Capacity[1]);
                        }

                        let Temperatures = nvme[1].matchAll(/^Temperature: *([\d]*)[ \S]*$/gm);
                        for (const Temperature of Temperatures) {
                            data[nvmeNumber]['Temperatures'].push(Temperature[1]);
                        }

                        let Available_Spares = nvme[1].matchAll(/^Available Spare: *([\d]*%)[ \S]*$/gm);
                        for (const Available_Spare of Available_Spares) {
                            data[nvmeNumber]['Available_Spares'].push(Available_Spare[1]);
                        }

                        let Useds = nvme[1].matchAll(/^Percentage Used: *([ \S]*)%$/gm);
                        for (const Used of Useds) {
                            data[nvmeNumber]['Useds'].push(Used[1]);
                        }

                        let Reads = nvme[1].matchAll(/^Data Units Read:[^\[]*\[([ \S]*)\]$/gm);
                        for (const Read of Reads) {
                            data[nvmeNumber]['Reads'].push(Read[1]);
                        }

                        let Writtens = nvme[1].matchAll(/^Data Units Written:[^\[]*\[([ \S]*)\]$/gm);
                        for (const Written of Writtens) {
                            data[nvmeNumber]['Writtens'].push(Written[1]);
                        }

                        let Cycles = nvme[1].matchAll(/^Power Cycles: *([ \S]*)$/gm);
                        for (const Cycle of Cycles) {
                            data[nvmeNumber]['Cycles'].push(Cycle[1]);
                        }

                        let Hours = nvme[1].matchAll(/^Power On Hours: *([ \S]*)$/gm);
                        for (const Hour of Hours) {
                            data[nvmeNumber]['Hours'].push(Hour[1]);
                        }

                        let Shutdowns = nvme[1].matchAll(/^Unsafe Shutdowns: *([ \S]*)$/gm);
                        for (const Shutdown of Shutdowns) {
                            data[nvmeNumber]['Shutdowns'].push(Shutdown[1]);
                        }

                        let States = nvme[1].matchAll(/^nvme\S+(( *\d+\.\d{2}){22})/gm);
                        for (const State of States) {
                            data[nvmeNumber]['States'].push(State[1]);
                            const IO_array = [...State[1].matchAll(/\d+\.\d{2}/g)];
                            if (IO_array.length > 0) {
                                data[nvmeNumber]['r_kBs'].push(IO_array[1]);
                                data[nvmeNumber]['r_awaits'].push(IO_array[4]);
                                data[nvmeNumber]['w_kBs'].push(IO_array[7]);
                                data[nvmeNumber]['w_awaits'].push(IO_array[10]);
                                data[nvmeNumber]['utils'].push(IO_array[21]);
                            }
                        }
                    }

                    let output = '';
                    for (const [i, nvme] of data.entries()) {
                        if (i > 0) output += '<br><br>';

                        if (nvme.Models.length > 0) {
                            output += colorizeSsdModel(nvme.Models[0], 100 - Number(nvme.Useds[0]));

                            if (nvme.Integrity_Errors.length > 0) {
                                for (const nvmeIntegrity_Error of nvme.Integrity_Errors) {
                                    if (nvmeIntegrity_Error != 0) {
                                        output += ` (`;
                                        output += `0E: ${nvmeIntegrity_Error}-故障！`;
                                        if (nvme.Available_Spares.length > 0) {
                                            output += ', ';
                                            for (const Available_Spare of nvme.Available_Spares) {
                                                output += `备用空间: ${Available_Spare}`;
                                            }
                                        }
                                        output += `)`;
                                    }
                                }
                            }
                        }

                        if (nvme.Capacitys.length > 0) {
                            output += ' | ';
                            for (const nvmeCapacity of nvme.Capacitys) {
                                output += `容量: ${nvmeCapacity.replace(/ |,/gm, '')}`;
                            }
                        }
                        output += '<br>';

                        if (nvme.Useds.length > 0) {
                            for (const nvmeUsed of nvme.Useds) {
                                output += `寿命: ${colorizeSsdLife(100-Number(nvmeUsed))} `;
                                if (nvme.Reads.length > 0) {
                                    output += '(';
                                    for (const nvmeRead of nvme.Reads) {
                                        output += `已读${nvmeRead.replace(/ |,/gm, '')}`;
                                        output += ')';
                                    }
                                }

                                if (nvme.Writtens.length > 0) {
                                    output = output.slice(0, -1);
                                    output += ', ';
                                    for (const nvmeWritten of nvme.Writtens) {
                                        output += `已写${nvmeWritten.replace(/ |,/gm, '')}`;
                                    }
                                    output += ')';
                                }
                            }
                        }

                        if (nvme.Temperatures.length > 0) {
                            output += ' | ';
                            for (const nvmeTemperature of nvme.Temperatures) {
                                output += `温度: ${colorizeSsdTemp(nvmeTemperature)}`;
                            }
                        }

                        if (nvme.utils.length > 0) {
                            output += ' | ';
                            for (const nvme_util of nvme.utils) {
                                output += `负载: ${colorizeSsdLoad(nvme_util)}`;
                            }
                        }
                        output += '<br>';

                        if (nvme.States.length > 0) {
                            output += 'I/O: ';
                            if (nvme.r_kBs.length > 0 || nvme.r_awaits.length > 0) {
                                output += '读-';
                                if (nvme.r_kBs.length > 0) {
                                    for (const nvme_r_kB of nvme.r_kBs) {
                                        var nvme_r_mB = `${nvme_r_kB}` / 1024;
                                        nvme_r_mB = nvme_r_mB.toFixed(2);
                                        output += `速度${colorizeIoSpeed(nvme_r_mB)}`;
                                    }
                                }
                                if (nvme.r_awaits.length > 0) {
                                    for (const nvme_r_await of nvme.r_awaits) {
                                        output += `, 延迟${colorizeIoLatency(nvme_r_await)}`;
                                    }
                                }
                            }

                            if (nvme.w_kBs.length > 0 || nvme.w_awaits.length > 0) {
                                if (nvme.r_kBs.length > 0 || nvme.r_awaits.length > 0) {
                                    output += ' / ';
                                }
                                output += '写-';
                                if (nvme.w_kBs.length > 0) {
                                    for (const nvme_w_kB of nvme.w_kBs) {
                                        var nvme_w_mB = `${nvme_w_kB}` / 1024;
                                        nvme_w_mB = nvme_w_mB.toFixed(2);
                                        output += `速度${colorizeIoSpeed(nvme_w_mB)}`;
                                    }
                                }
                                if (nvme.w_awaits.length > 0) {
                                    for (const nvme_w_await of nvme.w_awaits) {
                                        output += `, 延迟${colorizeIoLatency(nvme_w_await)}`;
                                    }
                                }
                            }
                        }

                        if (nvme.Cycles.length > 0) {
                            output += '<br>';
                            for (const nvmeCycle of nvme.Cycles) {
                                output += `通电: ${nvmeCycle.replace(/ |,/gm, '')}次`;
                            }

                            if (nvme.Shutdowns.length > 0) {
                                output += ', ';
                                for (const nvmeShutdown of nvme.Shutdowns) {
                                    output += `不安全断电${nvmeShutdown.replace(/ |,/gm, '')}次`;
                                    break
                                }
                            }

                            if (nvme.Hours.length > 0) {
                                output += ', ';
                                for (const nvmeHour of nvme.Hours) {
                                    output += `累计${nvmeHour.replace(/ |,/gm, '')}小时`;
                                }
                            }
                        }
                    }
                    return output;

                } else {
                    return `提示: 未安装 NVMe硬盘 或已直通 NVMe 控制器!`;
                }
            },
        },
        {
            itemId: 'sata_status',
            colspan: 2,
            printBar: false,
            title: gettext('SATA硬盘'),
            textField: 'sata_status',
            renderer: function(value) {
                function colorizeHddTemp(temp) {
                    const tempNum = parseFloat(temp);
                    if (tempNum < 40) return `<span style="color:green; font-weight:bold;">${temp}°C</span>`;
                    if (tempNum < 50) return `<span style="color:orange; font-weight:bold;">${temp}°C</span>`;
                    return `<span style="color:red; font-weight:bold;">${temp}°C</span>`;
                }
                if (value.length > 0) {
                try {
                const jsonData = JSON.parse(value);
                if (jsonData.standy === true) {
                return '休眠中';
                }
                let output = '';
                if (jsonData.model_name) {
                output = `<strong>${jsonData.model_name}</strong><br>`;
                        if (jsonData.temperature?.current !== undefined) {
                        output += `温度: <strong>${colorizeHddTemp(jsonData.temperature.current)}</strong>`;
                        }
                        if (jsonData.power_on_time?.hours !== undefined) {
                        if (output.length > 0) output += ' | ';
                        output += `通电: ${jsonData.power_on_time.hours}小时`;
                        if (jsonData.power_cycle_count) {
                        output += `, 次数: ${jsonData.power_cycle_count}`;
                        }
                        }
                        if (jsonData.smart_status?.passed !== undefined) {
                        if (output.length > 0) output += ' | ';
                        output += 'SMART: ' + (jsonData.smart_status.passed ? '正常' : '警告!');
                        }
                        return output;
                        }
                        } catch (e) {
                        }
                        let outputs = [];
                        let devices = value.matchAll(/(\s*(Model|Device Model|Vendor).*:\s*[\s\S]*?\n){1,2}^User.*\[([\s\S]*?)\]\n^\s*9[\s\S]*?\-\s*([\d]+)[\s\S]*?(\n(^19[0,4][\s\S]*?$){1,2}|\s{0}$)/gm);
                        for (const device of devices) {
                        let devicemodel = '';
                        if (device[1].indexOf("Family") !== -1) {
                        devicemodel = device[1].replace(/.*Model Family:\s*([\s\S]*?)\n^Device Model:\s*([\s\S]*?)\n/m, '$1 - $2');
                        } else if (device[1].match(/Vendor/)) {
                        devicemodel = device[1].replace(/.*Vendor:\s*([\s\S]*?)\n^.*Model:\s*([\s\S]*?)\n/m, '$1 $2');
                        } else {
                        devicemodel = device[1].replace(/.*(Model|Device Model):\s*([\s\S]*?)\n/m, '$2');
                        }
                        let capacity = device[3] ? device[3].replace(/ |,/gm, '') : "未知容量";
                        let powerOnHours = device[4] || "未知";
                        let deviceOutput = '';
                        if (value.indexOf("Min/Max") !== -1) {
                        let devicetemps = device[6]?.matchAll(/19[0,4][\s\S]*?\-\s*(\d+)(\s\(Min\/Max\s(\d+)\/(\d+)\)$|\s{0}$)/gm);
                        for (const devicetemp of devicetemps || []) {
                            deviceOutput = `<strong>${devicemodel}</strong><br>容量: ${capacity} | 已通电: ${powerOnHours}小时 | 温度: <strong>${colorizeHddTemp(devicetemp[1])}</strong>`;
                            outputs.push(deviceOutput);
                        }
                        } else if (value.indexOf("Temperature") !== -1 || value.match(/Airflow_Temperature/)) {
                        let devicetemps = device[6]?.matchAll(/19[0,4][\s\S]*?\-\s*(\d+)/gm);
                        for (const devicetemp of devicetemps || []) {
                        deviceOutput = `<strong>${devicemodel}</strong><br>容量: ${capacity} | 已通电: ${powerOnHours}小时 | 温度: <strong>${colorizeHddTemp(devicetemp[1])}</strong>`;
                        outputs.push(deviceOutput);
                        }
                        } else {
                        if (value.match(/\/dev\/sd[a-z]/)) {
                            deviceOutput = `<strong>${devicemodel}</strong><br>容量: ${capacity} | 已通电: ${powerOnHours}小时 | 提示: 设备存在但未报告温度信息`;
                            outputs.push(deviceOutput);
                        } else {
                            deviceOutput = `<strong>${devicemodel}</strong><br>容量: ${capacity} | 已通电: ${powerOnHours}小时 | 提示: 未检测到温度传感器`;
                            outputs.push(deviceOutput);
                        }
                        }
                        }
                        if (!outputs.length && value.length > 0) {
                        let fallbackDevices = value.matchAll(/(\/dev\/sd[a-z]).*?Model:([\s\S]*?)\n/gm);
                        for (const fallbackDevice of fallbackDevices || []) {
                            outputs.push(`${fallbackDevice[2].trim()}<br>提示: 设备存在但无法获取完整信息`);
                        }
                        }
                        return outputs.length ? outputs.join('<br>') : '提示: 检测到硬盘但无法识别详细信息';
                    } else {
                        return '提示: 未安装 SATA硬盘 或已直通 SATA控制器!';
                }
            }
        },
EOF

echo -e "正在修改: $pvemanagerlib..."
ln=$(sed -n '/pveversion/,+10{/},/{=;q}}' $pvemanagerlib)
sed -i "${ln}r $tmpf2" "$pvemanagerlib"
rm -f "$tmpf2"



####################   调整页面高度   ####################

echo -e "正在调整页面高度: $pvemanagerlib..."
disk_count=$(lsblk -d -o NAME | grep -cE 'sd[a-z]|nvme[0-9]')
height_increase=$((disk_count * 300))

node_status_new_height=$((400 + height_increase))
sed -i -r '/widget\.pveNodeStatus/,+5{/height/{s#[0-9]+#'$node_status_new_height'#}}' $pvemanagerlib
cpu_status_new_height=$((300 + height_increase))
sed -i -r '/widget\.pveCpuStatus/,+5{/height/{s#[0-9]+#'$cpu_status_new_height'#}}' $pvemanagerlib

ln=$(expr $(sed -n -e '/widget.pveDcGuests/=' $pvemanagerlib) + 10)
sed -i "${ln}a\ textAlign: 'right'," $pvemanagerlib
ln=$(expr $(sed -n -e '/widget.pveNodeStatus/=' $pvemanagerlib) + 10)
sed -i "${ln}a\ textAlign: 'right'," $pvemanagerlib



####################   修改全部完成后重启服务   ####################

echo -e "\n🔁 等待服务 pveproxy.service 重启..."
systemctl restart pveproxy.service

echo -e "\n✅ 修改完成, 请使用 Ctrl + F5 刷新浏览器 Proxmox VE Web 管理页面缓存\n"
