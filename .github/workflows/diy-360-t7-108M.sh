#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# Description: Build OpenWrt using GitHub Actions
#

name: Build OpenWrt

on:
  repository_dispatch:
  workflow_dispatch:
    inputs:
      ssh:
        description: 'SSH connection to Actions'
        required: false
        default: 'false'

env:
  REPO_URL: https://github.com/coolsnowwolf/lede
  REPO_BRANCH: master
  FEEDS_CONF: feeds.conf.default
  CONFIG_FILE: .config
  DIY_P1_SH: diy-part1.sh
  DIY_P2_SH: diy-part2.sh
  DIY_P3_SH: update-transmission.sh
  UPLOAD_BIN_DIR: false
  UPLOAD_FIRMWARE: true
  UPLOAD_COWTRANSFER: false
  UPLOAD_WETRANSFER: false
  UPLOAD_RELEASE: true
  TZ: Asia/Shanghai

jobs:
  build:
    runs-on: ubuntu-20.04

    steps:
    - name: Check Server Performance
      run: |
        echo "警告⚠"
        echo "分配的服务器性能有限，若选择的插件过多，务必注意CPU性能！"
        echo -e "已知CPU型号（降序）：7763，8370C，8272CL，8171M，E5-2673 \n"
        echo "--------------------------CPU信息--------------------------"
        echo "CPU物理数量：$(cat /proc/cpuinfo | grep "physical id" | sort | uniq | wc -l)"
        echo -e "CPU核心信息：$(cat /proc/cpuinfo | grep name | cut -f2 -d: | uniq -c) \n"
        echo "--------------------------内存信息--------------------------"
        echo "已安装内存详细信息："
        echo -e "$(sudo lshw -short -C memory | grep GiB) \n"
        echo "--------------------------硬盘信息--------------------------"
        echo "硬盘数量：$(ls /dev/sd* | grep -v [1-9] | wc -l)" && df -hT

    - name: Checkout
      uses: actions/checkout@main
      with:
          fetch-depth: 0

    - name: 释放Ubuntu磁盘空间
      uses: jlumbroso/free-disk-space@main
      with:
        # this might remove tools that are actually needed,
        # if set to "true" but frees about 6 GB
        tool-cache: true
        # all of these default to true, but feel free to set to
        # "false" if necessary for your workflow
        android: true
        dotnet: true
        haskell: true
        large-packages: true
        swap-storage: true

    - name: Initialization environment
      env:
        DEBIAN_FRONTEND: noninteractive
      run: |
        sudo rm -rf /etc/apt/sources.list.d/* /usr/share/dotnet /usr/local/lib/android /opt/ghc /etc/mysql /etc/php
        sudo -E apt-get -qq update
        sudo -E apt-get -qq install $(curl -fsSL https://raw.githubusercontent.com/Kisoul/openwrt-list/master/depends-ubuntu-2004)
        sudo -E apt-get -qq autoremove --purge
        sudo -E apt-get -qq clean
        sudo timedatectl set-timezone "$TZ"
        sudo mkdir -p /workdir
        sudo chown $USER:$GROUPS /workdir
    
    - name: Clone source code
      working-directory: /workdir
      run: |
        df -hT $PWD
        git clone $REPO_URL -b $REPO_BRANCH openwrt
        ln -sf /workdir/openwrt $GITHUB_WORKSPACE/openwrt
        
    - name: Cache Toolchain
      uses: klever1988/cachewrtbuild@main
      with:
        ccache: 'true'
        prefix: ${{ github.workspace }}/openwrt
        
    - name: Load custom feeds
      run: |
        [ -e $FEEDS_CONF ] && mv $FEEDS_CONF openwrt/feeds.conf.default
        chmod +x $DIY_P1_SH
        cd openwrt
        $GITHUB_WORKSPACE/$DIY_P1_SH

    - name: Update feeds
      run: cd openwrt && ./scripts/feeds update -a

    - name: Fix transmission
      run: |
        chmod +x $DIY_P3_SH
        cd openwrt
        $GITHUB_WORKSPACE/$DIY_P3_SH

    - name: Install feeds
      run: cd openwrt && ./scripts/feeds install -a -f

    - name: Load custom configuration
      run: |
        [ -e files ] && mv files openwrt/files
        [ -e $CONFIG_FILE ] && mv $CONFIG_FILE openwrt/.config
        chmod +x $DIY_P2_SH
        cd openwrt
        $GITHUB_WORKSPACE/$DIY_P2_SH

    - name: SSH connection to Actions
      uses: P3TERX/ssh2actions@v1.0.0
      if: (github.event.inputs.ssh == 'true' && github.event.inputs.ssh  != 'false') || contains(github.event.action, 'ssh')
      env:
        TELEGRAM_CHAT_ID: ${{ secrets.TELEGRAM_CHAT_ID }}
        TELEGRAM_BOT_TOKEN: ${{ secrets.TELEGRAM_BOT_TOKEN }}

    - name: Download package
      id: package
      run: |
        cd openwrt
        make defconfig
        make download -j8
        find dl -size -1024c -exec ls -l {} \;
        find dl -size -1024c -exec rm -f {} \;

    - name: Compile the firmware
      id: compile
      run: |
        cd openwrt
        echo -e "$(nproc) thread compile"
        make -j$(nproc) || make -j1 || make -j1 V=s
        echo "status=success" >> $GITHUB_OUTPUT
        grep '^CONFIG_TARGET.*DEVICE.*=y' .config | sed -r 's/.*DEVICE_(.*)=y/\1/' > DEVICE_NAME
        [ -s DEVICE_NAME ] && echo "DEVICE_NAME=_$(cat DEVICE_NAME)" >> $GITHUB_ENV
        echo "FILE_DATE=_$(date +"%Y%m%d%H%M")" >> $GITHUB_ENV

    - name: Check space usage
      if: (!cancelled())
      run: df -hT

    - name: Upload bin directory
      uses: actions/upload-artifact@main
      if: steps.compile.outputs.status == 'success' && env.UPLOAD_BIN_DIR == 'true'
      with:
        name: OpenWrt_bin${{ env.DEVICE_NAME }}${{ env.FILE_DATE }}
        path: openwrt/bin

    - name: Organize files
      id: organize
      if: env.UPLOAD_FIRMWARE == 'true' && !cancelled()
      run: |
        cd openwrt/bin/targets/*/*
        rm -rf packages
        echo "FIRMWARE=$PWD" >> $GITHUB_ENV
        echo "status=success" >> $GITHUB_OUTPUT

    - name: Upload firmware directory
      uses: actions/upload-artifact@main
      if: steps.organize.outputs.status == 'success' && !cancelled()
      with:
        name: OpenWrt_firmware${{ env.DEVICE_NAME }}${{ env.FILE_DATE }}
        path: ${{ env.FIRMWARE }}

    - name: Upload firmware to cowtransfer
      id: cowtransfer
      if: steps.organize.outputs.status == 'success' && env.UPLOAD_COWTRANSFER == 'true' && !cancelled()
      run: |
        curl -fsSL git.io/file-transfer | sh
        ./transfer cow --block 2621440 -s -p 64 --no-progress ${FIRMWARE} 2>&1 | tee cowtransfer.log
        echo "::warning file=cowtransfer.com::$(cat cowtransfer.log | grep https)"
        echo "url=$(cat cowtransfer.log | grep https | cut -f3 -d" ")" >> $GITHUB_OUTPUT

    - name: Upload firmware to WeTransfer
      id: wetransfer
      if: steps.organize.outputs.status == 'success' && env.UPLOAD_WETRANSFER == 'true' && !cancelled()
      run: |
        curl -fsSL git.io/file-transfer | sh
        ./transfer wet -s -p 16 --no-progress ${FIRMWARE} 2>&1 | tee wetransfer.log
        echo "::warning file=wetransfer.com::$(cat wetransfer.log | grep https)"
        echo "url=$(cat wetransfer.log | grep https | cut -f3 -d" ")" >> $GITHUB_OUTPUT

    - name: Generate release tag
      id: tag
      if: env.UPLOAD_RELEASE == 'true' && !cancelled()
      run: |
        echo "release_tag=$(date +"%Y.%m.%d-%H%M")" >> $GITHUB_OUTPUT
        touch release.txt
        [ $UPLOAD_COWTRANSFER = true ] && echo "🔗 [Cowtransfer](${{ steps.cowtransfer.outputs.url }})" >> release.txt
        [ $UPLOAD_WETRANSFER = true ] && echo "🔗 [WeTransfer](${{ steps.wetransfer.outputs.url }})" >> release.txt
        echo "status=success" >> $GITHUB_OUTPUT

    - name: Upload firmware to release
      uses: softprops/action-gh-release@v1
      if: steps.tag.outputs.status == 'success' && !cancelled()
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      with:
        tag_name: ${{ steps.tag.outputs.release_tag }}
        body_path: release.txt
        files: ${{ env.FIRMWARE }}/*

    - name: Delete workflow runs
      uses: GitRML/delete-workflow-runs@main
      with:
        retain_days: 1
        keep_minimum_runs: 3

    - name: Remove old Releases
      uses: dev-drprasad/delete-older-releases@v0.1.0
      if: env.UPLOAD_RELEASE == 'true' && !cancelled()
      with:
        keep_latest: 3
        delete_tags: true
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}



